# models:  character, level, team, match, round_transcript, action, item, item_type, skill

# a character has_many levels, which belong to character_classes and have abilities,
# proficiencies, etc..


# Most of the rules seem to be modelable with a system of callbacks.  So eg: after
# they have been hit, mages cast spells for the rest of the round.  One solution to
# modeling this is to have a round transcript for all characters, and have mages
# check the transcript to see if they have taken some amount of damage in that round
# before casting.  Another approach is to have a freeform bag of state that gets
# managed by callbacks.  So a mage has gotHit: true and an onRound callback that
# clears that bit of state.  Where possible, the first approach seems simpler.
# However,

class Character
  include Util
  ATTRS = :hp, :thaco, :damage, :init, :curr_hp, :ac, :state, :attacks, :attacks_remaining, :name, :level, :xp, :levels, :attribute_set

  attr_accessor *ATTRS

  def initialize(params = {})
    ATTRS.map { |s| send("#{s}=", params[s])}
    self.level ||= 1
    reset
  end

  def can_attack?
    attacks_remaining > 0 &&
      conscious?
  end

  def conscious?
    self.state == :active
  end

  def xp_value(opponent)
    self.level * 300
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
    tn = thaco - target.ac
    r  = roll("1d20")
    puts "#{self.name} attacks #{target.name} tn:#{tn} r:#{r}"
    (r >= tn) && target.take_damage(roll(damage))
    defeat(target) unless target.conscious?
  end

  def defeat(target)
    self.gain_xp target.xp_value(self)
  end

  def gain_xp(i)
    self.xp += i
    self.set_level level_for_xp(self.xp)
  end

  def set_level(n)
    now = self.level
    if n > now
      self.hp += 8 * (n - self.level)
      self.thaco -= ((self.level + 1)..n).to_a.select { |i| i.odd? }.size
    end
    self.level = n
  end

  def take_damage(amt)
    self.curr_hp -= amt
    self.state = :unconscious if curr_hp < 1
    self.state = :dead if curr_hp < -9
    puts "#{self.name} took #{amt} damage, in state:#{state}, hp:#{curr_hp}"
  end

  def reset_round
    self.attacks_remaining = self.attacks
  end

  def reset
    self.curr_hp = self.hp
    reset_round
    self.state = :active if curr_hp.to_i > 0
  end

  def roll_initiative
    roll(self.init || "1d10")
  end

  def attack_until_dead(target)
    while can_attack? && target.conscious?
      attack(target)
    end
  end
end

class Array
  def sum
    inject(0) { |m, x| m + x }
  end
end

class Item
  attr_accessor :weight, :cost
end

class Weapon < Item
  attr_accessor :damage
end

$filename ||= File.expand_path(__FILE__)

def reload!
  puts $filename
  puts File.read($filename)
  eval File.read($filename)
end

$i = 0
def make_char
  $i += 1
  i = $i
  Character.new({ :hp => 14, :thaco => 19, :damage => "1d10", :ac => 8, :attacks => 5, :game_class => "monk", :name => "monk#{i}" })
end


def fight_round(a, b)
  a.attack_until_dead b
  b.attack_until_dead a
end

def fight(a, b)
  a.to_a.map &:reset
  b.to_a.map &:reset
  while a.conscious? && b.conscious?
    a.to_a.map &:reset_round
    b.to_a.map &:reset_round
    fight_round a, b
  end
end


# to implement monks, I'll need at least character classes and martial arts.
# probably need to implement fighters and barbarians also.
