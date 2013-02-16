# for now, this holds my second pass at implementing AD&D-style character generation,
# and ultimately, fighting in a CLI.

require File.expand_path("../util", __FILE__)

class User
  attr_accessor :id
  def generate_character(params = { })
    Character.new params.merge(:user => self)
  end
end

class Round
  ATTRS = [:participants, :action_order, :fight]
  attr_accessor *ATTRS
  def initialize(fight, participants)
    @participants = participants
    @participants.map { |p| p.round_num += 1; p.reset_round }
    @fight = fight
    set_initiative!
    puts "\nstarting round!"
  end

  def set_initiative!
    @action_order = participants.map { |p| [p] * p.attacks_remaining }.flatten
  end

  def finished?
    self.participants.select { |p| p.conscious? }.map { |p| p.team }.uniq.size == 1
  end

  def fight_round
    action_order.each do |c|
      puts "c.inspect=#{c.inspect}"
      target = participants.select { |x| (c.team != x.team) && x.conscious? }.first
      puts "no enemies left for #{c.name}" if target.nil?
      return if target.nil?
      puts "#{c.character.name} of #{c.team} attacking #{target.character.name} of #{target.team}"
      c.attack target
    end
  end
end

class CharacterState
  include Util
  ATTRS = :character, :state, :primary_weapon, :curr_hp, :attacks_remaining, :base_armor, :team, :round_num
  attr_accessor *ATTRS

  def initialize(params = {})
    ATTRS.map { |s| send("#{s}=", params[s])}
    self.base_armor ||= 0
    self.team ||= self.name
    self.round_num ||= 0
    reset
  end

  def inspect
    "#{character.name} round:#{round_num}"
  end

  def reset
    self.curr_hp = character.hp
    self.round_num = 0
    reset_round
    self.state = :active if curr_hp.to_i > 0
  end

  def reset_round
    self.attacks_remaining = attacks_this_round
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
      [primary_weapon.damage, character.bonuses[:damage]].join(" ").strip
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

  def attacks_this_round
    floor, ceil = [character.attacks.floor, character.attacks.ceil]
    round_num.odd? ? floor : ceil
  end

  def conscious?
    self.state == :active
  end

  def on_hit(target)
    primary_weapon.blank? && on_unarmed_strike(target)
  end

  def attack(target)
    unless target.conscious?
      puts "#{target.name} is already down."
      return
    end

    unless conscious?
      puts "#{self.name} is unconscious"
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
    bonus = bonuses[:unarmed] && bonuses[:unarmed][:damage]
    Util.simplify(bonus) || "1d2"
  end

  def defeat(target)
    self.gain_xp target.xp_value(self)
  end

  def attribute_bonuses
    []
  end

  def bonuses
    # build a bigass hash of bonuses per-thing.
    all_bonuses = self.levels.map { |l| l.bonuses } + self.attribute_bonuses
    all_bonuses.array_flatten.compact.inject({ }) { |m,x| m.join(x) }
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
    result = classes.group_by { |x| x }
    h.keys.each do |k|
      result[k.char_class] = h[k].size
    end
    result
  end

  def wp_slots_open
    self.levels.map { |l| l.wp_slots - l.weapon_profs.size }.sum
  end
end

class Level
  ATTRS = :character, :char_class, :n, :weapon_profs, :non_weapon_profs, :wp_slots, :nwp_slots, :level_bonuses
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

  def bonuses
    self.weapon_profs.map { |wp| wp.bonuses } + self.level_bonuses
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

    def on_unarmed_strike(opponent)
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
  reqs :str => 15, :wis => 15, :dex => 15, :con => 11
  first_level :wp_slots => 4, :nwp_slots => 3

  class << self
    def hd
      8
    end

    def buff(character)

    end
  end
end
