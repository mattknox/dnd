# eventually, I'll refactor the domain logic of D&D to here.

class AttributeSet
  # This is a set of data needed for PCs and some NPCs.
  ATTRS = :str, :con, :dex, :int, :wis, :chr
  attr_accessor *ATTRS
end

class CharacterFactory
  extend Util
  def self.three_die_in_order
    pc = AttributeSet.new
    AttributeSet::ATTRS.each do |a|
      pc.send("#{a}=", roll("3d6"))
    end
    pc
  end

  def self.three_die_twice
    pc = AttributeSet.new
    AttributeSet::ATTRS.each do |a|
      r = [roll("3d6"), roll("3d6")].max
      pc.send("#{a}=", r)
    end
    pc
  end

  def self.four_dice
    pc = AttributeSet.new
    AttributeSet::ATTRS.each do |a|
      r = [roll("1d6"), roll("1d6"), roll("1d6"), roll("1d6")].sort.last(3).sum
      pc.send("#{a}=", r)
    end
    pc
  end

  def self.twelve_rolls
    roll_n_take_m 12, 6
  end

  def self.roll_n_take_m(n, m, die = "3d6")
    (1..n).map { roll die }.sort.last m
  end
end




$dfilename ||= File.expand_path(__FILE__)

def reload_domain!
  puts $dfilename
  puts File.read($dfilename)
  eval File.read($dfilename)
end


__END__
