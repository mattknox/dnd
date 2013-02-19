load "lib/character.rb"

u = User.new
u.id = 1

f = u.generate_character(:name => "fighter", :scheme => :three_dice_twice)
p = u.generate_character(:name => "paladin", :scheme => :three_dice_twice)
m = u.generate_character(:name => "monk", :scheme => :three_dice_twice)

f.set_attrs!
p.set_attrs!

p.chr = 17
p.str = 13
f.str = 18
m.str = m.dex = m.wis = m.con = 15


f.take_level Fighter
f.levels.first.take_wp Weapon.find_by_name(:katana)
f.levels.first.specialize Weapon.find_by_name(:katana)

p.take_level Paladin
p.levels.first.take_wp Weapon.find_by_name(:katana)

m.take_level Monk
m.levels.first.take_skill :karate
m.levels.first.take_skill :boxing

fs = f.new_state
fs.primary_weapon = Weapon.find_by_name(:katana)

ps = p.new_state
ps.primary_weapon = Weapon.find_by_name(:katana)

ms = m.new_state


def fight_round(a, b)
  # a won initiative
  while [a, b].all?(&:conscious?) && (a.can_attack? || b.can_attack?)
    a.attack b if a.can_attack?
    b.attack a if b.can_attack?
  end
end

def fight(a, b)
  a.reset
  b.reset
  fight_round(a,b)
end
