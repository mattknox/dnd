# for now, this holds my second pass at implementing AD&D-style character generation,
# and ultimately, fighting in a CLI.

load "util.rb"

class User
  attr_accessor :id
  def generate_character(params = { })
    Character.new params.merge(:user => self)
  end
end

class CharacterState
  include Util
  ATTRS = :character, :state, :primary_weapon, :curr_hp, :attacks_remaining, :base_armor
  attr_accessor *ATTRS

  def initialize(params = {})
    ATTRS.map { |s| send("#{s}=", params[s])}
    self.base_armor ||= 0
    reset
  end

  def reset
    self.curr_hp = character.hp
    reset_round
    self.state = :active if curr_hp.to_i > 0
  end

  def reset_round
    self.attacks_remaining = character.attacks
  end

  def name; character.name end

  def to_hit(target)
    character.to_hit + situational_bonus(:attack, target) + Util.simplify(character.bonuses[:to_hit]).to_i
  end

  def armor_rating
    base_armor + situational_bonus(:defense, self)
  end

  def damage
    if primary_weapon
      [primary_weapon.damage, character.bonuses[:damage]].join(" ")
    else
      character.unarmed_damage
    end
  end

  def take_damage(amt)
    self.curr_hp -= amt
    self.state = :unconscious if curr_hp < 1
    self.state = :dead if curr_hp < -9
    puts "#{self.name} took #{amt} damage, in state:#{state}, hp:#{curr_hp}"
  end

  def situational_bonus(sym, target)
    0
  end

  def can_attack?
    attacks_remaining > 0 &&
      conscious?
  end

  def conscious?
    self.state == :active
  end

  def attack(target)
    unless target.conscious?
      puts "#{target.name} is already down."
      return
    end

    unless can_attack?
      puts "#{self.name} has no attacks left"
      return
    end

    self.attacks_remaining -= 1
    tn = 10 + target.armor_rating - to_hit(target)
    r  = Util.roll("1d20")
    puts "#{self.name} attacks #{target.name} tn:#{tn} r:#{r}"
    (r >= tn) && target.take_damage(Util.roll(damage))
    character.defeat(target.character) unless target.conscious?
  end
end

class Character
  USER_ATTRS = :name, :scheme, :user, :roller, :level, :levels, :hp, :xp, :to_hit
  ATTRS = :str, :con, :dex, :int, :wis, :chr

  attr_accessor *USER_ATTRS
  attr_accessor *ATTRS
  def initialize(params = { })
    USER_ATTRS.map { |s| send("#{s}=", params[s])}
    self.roller ||= Util
    self.level = [1, self.level.to_i].max
    self.levels = []
    self.hp ||= 0
    self.xp ||= 0
    self.to_hit ||= 0
  end

  def xp_value(opponent)
    level * 300
  end

  def unarmed_damage
    "1d2"
  end

  def defeat(target)
    self.gain_xp target.xp_value(self)
  end

  def bonuses
    # build a bigass hash of bonuses per-thing.
    h = { }
    bl = self.levels.map { |l| l.weapon_profs.map { |wp| wp.bonuses }}.array_flatten.compact
    bl.inject({ }) { |m,x| m.join(x) }
  end

  def attacks
    1 + Util.simplify(bonuses[:attack]).to_f
  end

  def defeat(target)
    self.gain_xp target.xp_value(self)
  end

  def gain_xp(i)
    self.xp += i
    self.set_level Util.level_for_xp(self.xp)
  end

  def set_level(n)
    now = self.level
    if n > now

    end
    self.level = n
  end

  def set_attrs!
    raise "haven't implemented that chargen method" unless scheme == :three_dice_twice
    # TODO: generalize a bit.

    ATTRS.each do |a|
      send("#{a}=", roller.roll("3d6"))
    end
  end

  def new_state
    CharacterState.new(:character => self, :state => :active, :curr_hp => self.hp)
  end

  def can_be?(char_class)
    char_class.available_to? self
  end

  def can_take_level?
    self.level > self.levels.length
  end

  def take_level(char_class)
    if can_take_level? && can_be?(char_class)
      char_class.buff(self)
    end
  end

  def classes
    self.levels.map { |l| l.char_class }.uniq
  end

  def class_levels
    h = self.levels.group_by { |x| x }
    h.keys.each do |k|
      h[k] = h[k].size
    end
  end

  def wp_slots_open
    self.levels.map { |l| l.wp_slots - l.weapon_profs.size }.sum
  end
end

class Level
  ATTRS = :character, :char_class, :n, :weapon_profs, :non_weapon_profs, :wp_slots, :nwp_slots
  attr_reader *ATTRS
  def initialize(params)
    ATTRS.map { |s| instance_variable_set("@#{s}".to_sym, params[s])}
    @weapon_profs ||= []
    @wp_slots ||= 0
  end

  def self.build_level(character, char_class, n, is_first = false)
    h = { :character => character, :char_class => char_class, :n => n}
    if is_first
      Level.new(h.merge(char_class.first_level_benefits))
    else
      Level.new(h.merge(char_class.next_level_benefits(n)))
    end
  end

  def take_wp(weapon)
    if self.char_class.can_use?(weapon) && wp_slots > weapon_profs.size
      @weapon_profs << WeaponProficiency.new(weapon)
    end
  end

  def take_skill(skill)
    if wp_slots > weapon_profs.size
      @weapon_profs << skill
    end
  end

  def specialize(weapon)
    return if Fighter != self.char_class || character.levels.map { |l| l.weapon_profs }.flatten.find { |x| x.name == "#{weapon.name} spec"}
    @weapon_profs << Skill.new(:name => "#{weapon.name} spec",
                               :bonuses => {
                                 :damage => "2",
                                 :to_hit => "1",
                                 :attack => "0.5"
                               },
                               :cost => 1)
  end
end

SKILLS = {
  :karate => {
    :name => :karate,
    :cost => 1,
    :bonuses => {
      :unarmed_damage  => "base 1d6",
      :unarmed_attacks => "base 3"}},
  :boxing => {
    :name => :boxing,
    :cost => 1,
    :bonuses => {
      :unarmed_damage  => "+ 2",
      :unarmed_to_hit  => "+ 1",
      :unarmed_attacks => "+ 1"
    }
  }
}

class Skill
  ATTRS = :name, :prereqs, :desc, :cost, :bonuses
  attr_reader *ATTRS
  def initialize(params)
    ATTRS.map { |s| instance_variable_set("@#{s}".to_sym, params[s])}
    @cost ||= 1
    @prereqs ||= []
  end

  def self.find_by_name(name)
    new(SKILLS[name]) if SKILLS.has_key? name
  end
end

class WeaponProficiency < Skill
  def initialize(x)
    if x.is_a? Weapon
      super(:name => x.name, :cost => 1, :prereqs => [])
    else
      # TODO: fix
      raise "not yet implemented"
    end
  end
end

class CharClass
  class << self
    def available_to?(c)
      requirements.all? { |k, v| c.send(k) >= v }
    end

    def reqs(h)
      (class << self; self; end).send(:define_method, :requirements) do
        h
      end
    end

    def first_level(h)
      (class << self; self; end).send(:define_method, :first_level_benefits) do
        h
      end
    end

    def buff(character)
      character.hp += self.hd
      character.levels << Level.build_level(character, self, next_level(character), character.levels.size == 0 )
    end

    def next_level(character)
      character.levels.select { |l| l.char_class == self }.size + 1
    end
  end
end

class Fighter < CharClass
  reqs :str => 9
  first_level :wp_slots => 4, :nwp_slots => 3

  def self.hd
    10
  end

  def self.can_use?(weapon)
    true
  end

  def self.next_level_benefits(n)
    if 0 == n % 3
      { :wp_slots => 1, :nwp_slots => 1}
    else
      { }
    end
  end

  def buff(character)
    self.to_hit += 1
    super
  end
end

class Weapon
  ATTRS = :name, :damage
  attr_reader *ATTRS
  def initialize(params)
    ATTRS.map { |s| instance_variable_set("@#{s}".to_sym, params[s])}
  end

  def self.find_by_name(name)
    raise unless :katana == name
    # TODO: generalize a bit.

    return Weapon.new(:name => :katana, :damage => "1d10")
  end
end

class Paladin < CharClass
  reqs :chr => 17, :str => 12
  first_level :wp_slots => 4, :nwp_slots => 3

  def self.hd
    10
  end

  def self.can_use?(weapon)
    true
  end
end

class Monk < CharClass
  reqs :str => 15

  def self.hd
    6
  end
end

require "test/unit"
require "mocha/setup"

class CharacterGenerationTest < Test::Unit::TestCase
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
    Util.stubs(:roll).with("3d6").returns 17
    Util.stubs(:roll).with("d20").returns 17
    f.set_attrs!
    f.take_level Fighter
    assert f.levels.first.take_wp Weapon.find_by_name(:katana)
    assert f.levels.first.specialize Weapon.find_by_name(:katana)
    assert_nil f.levels.first.specialize(Weapon.find_by_name(:katana)), "you cannot double-specialize"
    assert_equal f.wp_slots_open, 2

    p.set_attrs!
    p.take_level Paladin

  end
end
