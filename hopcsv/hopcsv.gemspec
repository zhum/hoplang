# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "hopcsv"
  s.version = "0.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Sergey Zhumatiy, Evan Weaver"]
  s.date = "2012-06-25"
  s.description = "A pure-C CSV parser for HOPSA. Based on Ccsv project."
  s.email = ""
  s.extensions = ["ext/extconf.rb"]
  s.extra_rdoc_files = ["CHANGELOG", "LICENSE", "README.rdoc", "ext/hopcsv.c", "ext/hopcsv.h", "ext/extconf.rb"]
  s.files = ["CHANGELOG", "LICENSE", "Manifest", "README.rdoc", "Rakefile", "ext/hopcsv.c", "ext/hopcsv.h", "ext/extconf.rb", "test/data.csv", "test/data_small.csv", "test/unit/test_hopcsv.rb", "hopcsv.gemspec"]
  s.homepage = "http://github.com/zhum/hopcsv"
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Hopcsv", "--main", "README.rdoc"]
  s.require_paths = ["lib", "ext"]
  s.rubyforge_project = "hopcsv"
  s.rubygems_version = "1.8.23"
  s.summary = "A pure-C CSV parser for HOPSA. Based on Ccsv project."
  s.test_files = ["test/unit/test_hopcsv.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
