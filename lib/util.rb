module Util
  def self.roll_die(die_faces)
    1 + rand(die_faces.to_i)
  end

  # def self.roll(rollspec)
  #   # this takes a rollspec like 5d10+10 and calculates it.
  #   # need to eventually figure out how to handle d20 (without the 1)
  #   rolls, other = rollspec.split(/\s+/).partition { |x| x.match /d/i }
  #   mults, constants = other.partition { |b| b.match /x/ }
  #   mult = mults.map { |x| x.gsub(/x/i, "").to_f}.mult_product

  #   res = constants.map { |s| s.to_f }.sum + rolls.map { |s| roll_diespec s }.sum
  #   final = (res * mult).to_i
  #   puts "rollspec:#{rollspec} res:#{res} mult:#{mult} final:#{final}"
  #   final
  # end

  def self.parse_rollspec(rollspec)
    bases, other = rollspec.to_s.split(/\s+/).partition { |b| b.match /base/i }
    rolls, other = other.partition { |x| x.match /d/i }
    rollhash = rolls.inject(Hash.new(0)) {|m,x| n, faces = x.split(/d/i); m[faces] += [n.to_i, 1].max; m }
    base = bases.map { |b| b.gsub(/base */i, "")}.sort { |a, b| max(a) <=> max(b)}.last
    mults, constants = other.partition { |b| b.match /x/i }
    mult  = mults.map { |x| x.gsub(/x/i, "").to_f}.mult_product
    const = constants.map { |x| x.to_f }.sum
    unspecd_dice = rollhash.delete(nil)
    if base && !base.match(/d/i)
      # base is a pure numeric
      const += base.to_f
      base = nil
    end
    if 1 != rollhash.size && unspecd_dice
      raise "rollspec: #{rollspec} is invalid."
    elsif rollhash.size == 1
      rollhash[rollhash.keys.first] += unspecd_dice.to_i
    end

    rollhash.tap do |h|
      h[:mult] = mult if mult != 1
      h[:const] = const if const.to_f != 0.0
      h[:base] = base if base && base.to_f != 0.0
    end
  end

  def self.max(rollspec)
    if rollspec.match(/d/i)
      dice, faces = rollspec.split(/d/i)
      dice.to_i * faces.to_i
    else
      rollspec.to_i
    end
  end

  def self.roll(rollspec)
    h = parse_rollspec(rollspec)
    mult = h.delete(:mult)
    (h.delete(:base).to_i + h.delete(:const).to_i + h.map { |faces, times| roll_dice(times, faces)}.sum) * mult
  end

  def self.roll_diespec(diespec)
    times, faces = diespec.split(/d/i)
    times = 1 if times.to_i == 0
  end

  def self.roll_dice(times, faces)
    (1..[1, times.to_i].max).map { |i| roll_die(faces)}.sum
  end

  def self.simplify(rollspec)
    h = parse_rollspec(rollspec)
    m, c, b = h.delete_many(:mult, :const, :base)
    arr = [b, c]
    arr.map! { |x| "#{x * m}"} if m
    str = h.map { |faces, n| "#{n * m }d#{faces}"}.join " "
    (arr + [str]).join(" ").strip
  end

  def self.level_for_xp(xp)
    l = 1
    while xp > 0
      xp -= l * 1000
      l += 1 if xp >= 0
    end
    l
  end

  def self.combine_bonuses(bonuses)
    # this method should take in a bunch of bonuses of the form:
    # base 3
    # 1
    # 1d6
    # x3
    # -2, etc and return a composite value.
    bases, other = bonuses.partition { |b| b.match /base/i }
    base = bases.map { |b| b.gsub(/base */i, "").to_i }.sort.last
    ostr = other.join(" ")
    "#{base} #{ostr} ".strip
  end
end

class Array
  def sum
    inject(0) { |m, x| m + x }
  end

  def mult_product
    inject(1) { |m, x| m * x }
  end

  def array_flatten
    flatten
  end
end

class Hash
  def join(other)
    ret = self.clone
    other_keys = other.keys - self.keys
    ret.keys.each do |k|
      v = other[k]
      ret[k] = "#{ret[k]} #{v}" if v
    end
    other_keys.each do |k|
      ret[k] = other[k]
    end
    ret
  end

  def array_flatten
    self
  end

  def delete_many(*args)
    args.map { |x| delete(x)}
  end
end
