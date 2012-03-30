module Hopsa

  def load_program(text)
    Hopsa::Config.load
    Hopsa::Param.load
    Hopsa::Function.load
    return TopStatement.createNewRetLineNum(nil,text,0)
  end

  def self.db_load
    # load database drivers
    Dir['./hop_db_*.rb'].each do |db|
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
