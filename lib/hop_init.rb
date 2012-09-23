module Hopsa

  #
  # Load and execute Hoplang program text,
  # text is Array (sic!) of text lines.
  #
  #  Options:
  #   :stdout - true(default) -> print to stdout, false -> put output into Hopsa::OUT array
  #
  def load_program(text,opts={})
    unless Hopsa.init_done?
      Hopsa::Function.load
      Hopsa::OUT.clear
      Hopsa.init_done
    end
    Hopsa::Config.load
    Hopsa::Param.load
    Config['local']['stdout']=opts[:stdout] unless opts[:stdout].nil?
    return TopStatement.createNewRetLineNum(nil,text,0)
  end

  #
  #  Loads and executes Hoplang program from file
  #  See load_program
  def load_file(name,opts={})
    text=[]
    File.open(name).each do |line|
      text.push line
    end
    load_program(text,opts)
  end

  def init_done?
    @@init_done
  end
  
  def init_done
    @@init_done=true
  end

  # Load all available database drivers
  #
  def self.db_load
    Dir[(Pathname.new(File.expand_path('..', __FILE__))+'hop_db_*.rb').to_s].each do |db|
      # temporary disable cassandra
      # next if db =~ /cassandra/
      hop_warn "DB Driver load: #{db.to_s}"
      begin
        require db.to_s
        db =~ /hop_db_(.+)\.rb/
        @@hoplang_databases.push $1
        hop_warn "OK! (#{$1})"
      rescue LoadError => e
        hop_warn "DB Driver load failed (but ignored): #{db.to_s} (#{e.message})"
      rescue => e
        hop_warn "DB Driver init failed: #{db.to_s} (#{e.message})"
      end
    end
  end


  @@hoplang_databases=[]
  db_load

  private
    @@init_done=false

end
