module Hopsa

  #
  # Load and execute Hoplang program text,
  # text is Array (sic!) of text lines.
  #
  def load_program(text)
    Hopsa::Config.load
    Hopsa::Param.load
    Hopsa::Function.load
    return TopStatement.createNewRetLineNum(nil,text,0)
  end

  #
  #  Loads and executes Hoplang program from file
  #
  def load_file(name)
    text=[]
    File.open(name).each do |line|
      text.push line
    end
    ex=load_program(text)
    ex.hop
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

end
