require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name        = 'hoplang'
    gemspec.summary     = 'Innovative parallel cool data strams processing language'
    gemspec.description = 'Hoplang is innovative parallel cool data strams processing language'
    gemspec.email       = 'serg@parallel.ru, adinetz@gmail.com'
    gemspec.homepage    = 'http://github.com/zhum/hoplang'
    gemspec.authors     = ['Andrey Adinetz', 'Sergey Zhumatiy']
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts 'Jeweler not available. Install it with: sudo gem install jeweler'
end

begin
  #require 'spec/rake/spectask'
  require 'rspec/core/rake_task'

  desc 'Default: run unit tests.'
  task :default => :spec

  desc 'Test functions.'
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = 'spec/**/*_spec.rb'
    t.verbose = true
    t.rspec_opts = ['-cfs']
  end
rescue LoadError
  puts 'RSpec not available. Install it with: sudo gem install rspec'
end

begin
  require 'yard'
  YARD::Rake::YardocTask.new(:yard) do |t|
    t.options = ['--title', 'Hoplang Documentation']
    t.files = ['./*.rb']
    if ENV['PRIVATE']
      t.options.concat ['--protected', '--private']
    else
      t.options.concat ['--protected', '--no-private']
    end
  end
rescue LoadError
  puts 'Yard not available. Install it with: sudo gem install yard'
end

desc 'Fast local build/install gem. For debugging purporses.'
task :local do
  sh 'rm -rf pkg'
  Rake::Task[:build].invoke
  sh 'yes | gem uninstall hoplang; gem install --local --no-ri --no-rdoc pkg/hoplang*.gem'
end
