# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "hopcsv"
  s.version = "0.4.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Sergey Zhumatiy"]
  s.date = "2012-09-24"
  s.description = "A pure-C CSV parser for HOPSA. Based on Ccsv project. Works fast and efficient. Based on ccsv by Evan Weaver"
  s.email = "serg@parallel.ru"
  s.extensions = ["ext/extconf.rb"]
  s.extra_rdoc_files = ["CHANGELOG", "LICENSE", "README.rdoc", "ext/extconf.rb", "ext/hopcsv.c", "ext/hopcsv.h"]
  s.files = ["CHANGELOG", "LICENSE", "Manifest", "README.rdoc", "Rakefile", "ext/extconf.rb", "ext/hopcsv.c", "ext/hopcsv.h", "hopcsv.gemspec", "test/data.csv", "test/data_small.csv", "test/unit/test_hopcsv.rb", "test/unit/test_ccsv.rb"]
  s.homepage = "http://github.com/zhum/hopcsv"
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Hopcsv", "--main", "README.rdoc"]
  s.require_paths = ["ext"]
  s.rubyforge_project = "hopcsv"
  s.rubygems_version = "1.8.23"
  s.summary = "A pure-C CSV parser for HOPSA. Based on Ccsv project."
  s.test_files = ["test/unit/test_ccsv.rb", "test/unit/test_hopcsv.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
