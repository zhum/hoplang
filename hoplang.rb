require 'rubygems'
require 'yaml'

#TODO: correct implementation
class Hash
  def to_csv2
    return self.to_a.flatten.join(';')
  end

  def to_csv
    return self.values.flatten.join(';')
  end
end

require './hop_errors.rb'
require './hop_core.rb'
require './hop_varstore.rb'
require './hop_expression.rb'
require './hop_statement.rb'
require './hop_stance.rb'
require './hop_config.rb'

module Hopsa


  def load_program(text)
    Hopsa::Config.load
    return TopStatement.createNewRetLineNum(nil,text,0)
  end

  @@hoplang_databases=[]
  # load database drivers
  Dir['./hop_db_*.rb'].each do |db|
    warn "DB Driver load: #{db.to_s}"
    begin
      require db.to_s
      db =~ /hop_db_(.+)\.rb/
      @@hoplang_databases.push $1
    rescue LoadError => e
      warn "DB Driver load failed (but ignored): #{db.to_s} (#{e.message})"
    rescue => e
      warn "DB Driver init failed: #{db.to_s} (#{e.message})"
    end
  end

end

