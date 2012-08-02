# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "./hop_version.rb"

Gem::Specification.new do |s|
  s.name        = "HOPSA"
  s.version     = Hopsa::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Andrey Adinetz, Sergey Zhumatiy"]
  s.email       = ["adinetz@gmail.com,serg@parallle.ru"]
  s.homepage    = "http://hopsa.parallel.ru/"
  s.summary     = %q{Language for data streams processing}
  s.description = %q{Use "./hpl" to run interpreter. See http://github.com/zhum/hoplang wiki for syntax.}

  s.rubyforge_project = "HOPSA"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
