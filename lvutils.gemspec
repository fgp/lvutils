Gem::Specification.new do |s|
  s.name        = 'lvutils'
  s.version     = '0.1'
  s.date        = '2013-03-20'
  s.summary     = "Utilities for dealing with LVM logical volumes"
  s.description = "A sim"
  s.authors     = ["Florian Pflug"]
  s.email       = 'fgp@phlo.org'
  s.files       = %w{lib/lvutils/error.rb lib/lvutils/options.rb}
  s.homepage    = "https://github.com/fgp/lvutils"
  s.executables << "lvpeek"
end
