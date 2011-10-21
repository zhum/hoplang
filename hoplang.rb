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

  # load database drivers
  Dir['./hop_db_*.rb'].each do |db|
    warn "DB Driver load: #{db.to_s}"
    require db.to_s
  end

end

