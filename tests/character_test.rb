require "test/unit"
require "mocha/setup"
require File.expand_path("../../lib/character", __FILE__)

class CharacterTest < Test::Unit::TestCase
  # # wishful_thinking: I want to make this work:

  # c = current_user.generate_character :name => "alpha", :scheme => :three_dice_twice
  # # should have attributes set now.

  # c.take_level :fighter
  # should now have hitpoints

  # d = Weapon.find_by_name :daikyu
  # c.buy d
  # c.take_proficiency d
  # c.specialize d
  # k = Skill.find_by_name :karate
  # c.take_proficiency k

  def current_user
    @current_user ||= User.new.tap { |u| u.id = 1 }
  end

  def test_character_generation
    c = current_user.generate_character({ :name => "alpha",
                                          :scheme => :three_dice_twice})
    assert c.is_a? Character
    assert_equal "alpha", c.name, "name should have passed through"
    assert_equal c.user, current_user, "user should pass through"
    Util.stubs(:roll).with("3d6").returns 12
    c.set_attrs!
    assert_equal 12, c.str
    assert c.can_be?(Fighter), "str is high enough, so fighter should be available?"
    assert !c.can_be?(Paladin)
    assert c.take_level Fighter
    assert_equal 10, c.hp
    assert_equal 1, c.levels.size
    assert_equal [Fighter], c.classes
    assert_equal c.wp_slots_open, 4
    assert c.levels.first.take_wp Weapon.find_by_name(:katana)
    c.levels.first.take_skill Skill.find_by_name(:karate)
    assert_equal c.wp_slots_open, 2
  end

  def test_fight
    f = current_user.generate_character(:name => "fighter", :scheme => :three_dice_twice)
    p = current_user.generate_character(:name => "paladin", :scheme => :three_dice_twice)
    k = Weapon.find_by_name(:katana)

    Util.stubs(:roll).with("3d6").returns 17
    Util.stubs(:roll).with("1d20").returns 17 # most attacks will hit.
    Util.stubs(:roll).with("1d10").returns 3 # the paladin does 3 damage
    Util.stubs(:roll).with("1d10 2").returns 10 # the fighter does 10 damage
    f.set_attrs!
    f.take_level Fighter

    assert f.levels.first.take_wp k
    assert f.levels.first.specialize k
    assert_nil f.levels.first.specialize(k), "you cannot double-specialize"
    assert_equal f.wp_slots_open, 2


    p.set_attrs!
    p.take_level Paladin
    assert p.levels.first.take_wp k
    assert_equal p.wp_slots_open, 3
    assert_nil p.levels.first.specialize(k), "paladin cannot specialize"

    fs = f.new_state
    fs.primary_weapon = Weapon.find_by_name(:katana)
    assert_equal "1d10 2", fs.damage
    assert_equal 2, fs.attacks_remaining

    ps = p.new_state
    ps.primary_weapon = Weapon.find_by_name(:katana)
    assert_equal "1d10", ps.damage
    assert_equal 1, ps.attacks_remaining

    r = Round.new(nil, [ps, fs])
    assert_equal r.action_order, [ps, fs]
    r.fight_round

    assert fs.conscious?
    assert !ps.conscious?
    assert r.finished?
    assert_equal f.xp, 300

    fs.reset
    ps.reset

    p2 = p.clone
    p2.name = "paladin2"
    ps2 = p2.new_state
    ps2.primary_weapon = Weapon.find_by_name(:katana)
    assert_equal "1d10", ps2.damage
    assert_equal 1.0, ps2.attacks_remaining

    fs.round_num = 1
    ps2.team = ps.team = :team_paladin

    r2 = Round.new nil, [fs, ps, ps2]
    assert_equal r2.action_order, [fs, fs, ps, ps2]

    r2.fight_round

    assert fs.conscious?
    assert !ps.conscious?
    assert !ps2.conscious?
    assert r2.finished?
    assert_equal f.xp, 900
  end

  def test_monk
    Util.stubs(:roll).with("3d6").returns 17
    c = current_user.generate_character({ :name => "monk",
                                          :scheme => :three_dice_twice})
    c.set_attrs!
    assert_equal 17, c.str
    assert_equal 17, c.dex
    assert_equal 17, c.con
    assert_equal 17, c.wis

    assert c.can_take_level?
    assert c.take_level Monk
    assert_equal "1d3", c.unarmed_damage
  end
end
