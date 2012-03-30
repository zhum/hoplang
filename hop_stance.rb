class String
  def csv_escape
    gsub('"','\\"')
    if self == ''
      return '0'
    end
    if(self =~ /,/)
      return '"'+self+'"'
    end
    self
  end

  def to_class
    Object.const_get(self)
  end
end

class ConfigError <StandardError
end

module Hopsa
  # Statement, which process stream.
  # So, it has inPipe, which is connected to previous Hopstance output.
  class Hopstance < Statement

    def initialize(parent)
      super(parent)

      @varStore=VarStore.new(self)
    end

    attr_accessor :outPipe, :inPipe, :varStore

    def join_threads
      @@threads_mutex ||=Mutex.new

      @@threads ||= []
      loop do
        @@threads_mutex.synchronize do
          new_threads=[]
          @@threads.each do |t|
            hop_warn "T: #{t} #{t.status}"
            if t.status == false || t.status.nil?
              t.join
            else
              new_threads << t
            end
          end
          @@threads = new_threads
        end
        hop_warn "THREADS:#{@@threads.count}"
        sleep(0.1)
        break if @@threads.count==0
      end
#      @@threads=[]
    end

    def new_thread(name,&block)

      @@threads_mutex ||=Mutex.new

      @@threads ||= []
      @@threads_mutex.synchronize do
        t=Thread.new(&block)
        t.abort_on_exception=true
        @@threads.push(t)
        hop_warn "Thread #{name} started(#{t})"
      end
    end

    def self.initSourceDriver(parent, source, current_var, where)
      cfg_entry = Config["db_type_#{source}"]
      src=Config.varmap[source]
      type=src.nil? ? nil : src['type']
      if(parent.varStore.test_stream(source)) then
        source_stream=StreamDBDriver.new(parent, source, current_var, where)
      elsif(type=='csv') then
        source_stream=MyDatabaseEachHopstance.new(parent,source)
      elsif(@@hoplang_databases.include? type)
        typename=(type.capitalize+'DBDriver').to_class
        source_stream = typename.new parent, source, current_var, where
      elsif(type=='split') then
        #!!!!!!! zip.
        #!!!!!!! REWORK!!!!!
        i=1
        types_list=Array.new
        while name=Config["n_#{i}_#{source}"] do
          types_list << {:n => i, :name => name}
          i+=1
        end
        hopstance=SplitEachHopstance.new(parent, types_list)
        #^^^^^^^^^^^^^^^^^^^^^^^^^
        #source_stream=DBDRiverXXXXX
      else
        source_stream=CSVDriver.new(parent, source, current_var, where)
#        raise ConfigError("Cannot find source #{source}")
      end
      return source_stream
    end

  end

  class EachHopstance < Hopstance

    attr_reader :streamvar

    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless((line =~
        /^(\S+)\s*=\s*each\s+(\S+)\s+in\s+(\S+)(\s+where\s+(.*))?/) ||
             (line =~
        /^(\S+)\s*=\s*seq\s+(\S+)\s+in\s+(\S+)(\s+where\s+(.*))?/))

        raise SyntaxError.new(line)
      end

      streamvar,current_var,source,where=$1,$2,$3,$5
      source_driver=initSourceDriver(parent, source, current_var, where)

      hopstance=EachHopstance.new(parent)
      hopstance.varStore.addScalar(current_var)
      parent.varStore.addStream(streamvar)
      hopstance.varStore.copyStreamFromParent(streamvar,parent.varStore)

      hop_warn "ADDED STREAM: #{parent.varStore.object_id} #{streamvar}"

      return hopstance.init(text,pos,streamvar,current_var,source_driver,where)
    end

    def to_s
      "#EachHopstance(#{@streamvar}<-#{@source})"
    end
    # ret: self, new_pos
    def init(text,pos,streamvar,current_var,source,where)
      @streamvar,@current_var,@source=streamvar,current_var,source

      # parse predicate expression, if any
      @where_expr = HopExpr.parse_cond where if where
      #puts @where_expr.inspect if @where_expr

      pos+=1
      hop_warn ":: #{text[pos]}"
      hop_warn "EACH: #{streamvar},#{current_var},#{source},#{where}"
      # now create execution chains for body and final sections
      begin
        while true
          statement,pos=Statement.createNewRetLineNum(self,text,pos)
          @mainChain.add statement
        end
      rescue SyntaxError
        line,pos=Statement.nextLine(text,pos)
        hop_warn ">>#{line}<<"
        if line == 'final'
          # process final section!
          pos+=1
          begin
            while true
              hopstance,pos=Statement.createNewRetLineNum(self,text,pos)
              @finalChain.add hopstance
            end
          rescue SyntaxError
            line,pos=Statement.nextLine(text,pos)
            if line == 'end'
              return self,pos+1
            end
          end
        elsif line == 'end'
          return self,pos+1
        end
      end
      raise SyntaxError, "Syntax error line #{pos} (#{text[pos].chomp})"
    end

    def hop
      hop_warn "START main chain #{self.to_s} (#{@mainChain})"
#      hop_warn "MY VARSTORE BEFORE:\n#{varStore.print_store}"
#      hop_warn "PARENT VARSTORE:\n#{@parent.varStore.print_store}"
      varStore.merge(@parent.varStore)
#      hop_warn "MY VARSTORE AFTER:\n#{varStore.print_store}"

      new_thread "#{self.to_s}" do
        begin
          loop do
            value=@source.readSource
            break if value.nil?

            # process body
            varStore.set(@current_var, value)
            @mainChain.hop
          end
          # process final section
          hop_warn "START final chain #{self.to_s} (#{@finalChain})"
          @finalChain.hop

          hop_warn "FINISHED! #{self.to_s}\n-------------------------------"
          # write EOF to out stream
          do_yield(nil)
        rescue => e
          hop_warn "Exception in #{self.to_s} (#{@mainChain}: #{e}. "+e.backtrace.join("\t\n")
          raise
        end
      end #~Thread
    end

    def do_yield(hash)
      # push data into out pipe
#      hop_warn "!!! YIELD #{@streamvar} #{hash.inspect}"
      varStore.set(@streamvar,hash)
    end
  end

  class PrintEachHopstance < EachHopstance

    #
    #  nil   => not initialized yet
    #  false => do not print heads
    #  [...] => heads printed if needed, here are fields in right order
    @@out_heads=nil

    # read next source line and write it into @source_var
    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless(line =~ /print(\(\s*(\S*)\s*\))?\s+(\S.+)/)
        raise SyntaxError.new(line)
      end
      opts,src=$2,$3

      if opts.nil?
        opts=[]
      else
        opts=opts.split(/\s*,\s*/)
      end

      sources = src.split(/\s*,\s*/)
      hopstance=PrintEachHopstance.new(parent)
      source_drivers=[]
      sources.each do |s|
        source_drivers << initSourceDriver(parent, s, 'none', nil)
      end
      return hopstance.init(source_drivers,opts),pos+1
    end

    def init(sources,opts)
      @sources=sources
      @opts={}
      opts.each{|o|
        @opts[o.to_sym]=true
      }
      @index=0

      @out_format = :csv if @opts[:csv] || @opts[:raw]
      @@out_heads ||= @opts[:raw] ? false : nil

      @out_format ||= :csv if(not Config['local'].nil? and
                               Config['local']['out_format'] == 'csv')
      self
    end

    def to_s
      'PrintEachHopstance'
    end

    def hop
      new_thread  "#{self.to_s}" do
        while not (self.readSource).nil?
        end
      end
    end

    def readSource

      # read current source. switch to next if closed
      while (value=@sources[@index].readSource).nil?
        @sources.delete_at(@index)
        return nil if @sources.size==0
        next_index
      end

      next_index if @opts[:zip]

      if value['__hoplang_cols_order'].nil?
        hop_warn "BAD YIELD: #{value.inspect}"
        return value
      end

      if @out_format == :csv
         print_heads(value) if @@out_heads.nil?
         init_heads(value)  if @@out_heads == false
         print_csv(value)
      else
        puts "OUT>>#{value.inspect}"
      end
      value
    end

    protected

    def next_index
      @index +=1
      @index=0 if @index>=@sources.size
    end

    def print_heads(value)

      $hoplang_print_mutex ||= Mutex.new
      init_heads(value)
      # print header
      $hoplang_print_mutex.synchronize do
        puts value['__hoplang_cols_order']
      end
    end

    def init_heads(value)
      @@out_heads=value['__hoplang_cols_order'].split(/,/)
    end

    def print_csv(value)
      $hoplang_print_mutex ||= Mutex.new
      $hoplang_print_mutex.synchronize do
        out= @@out_heads.map {|key| value[key].to_s.csv_escape}.join(',')
        puts out unless out =~ /NaN/ #!!!!!!!!!!!!!!!!!!!!!   HACK   !!!!!!!!!!!!!!!!!!!!!!!
      end
    end

  end

  # a special hopstance which processes elements in strict sequential order
  # can be used, for instance, for easy implementation of accumulators
  class SeqHopstance < EachHopstance
    def hop
      hop_warn "START main chain SEQ #{self.to_s} (#{@mainChain})"
      varStore.merge(@parent.varStore)

      begin
        loop do
          value=@source.readSource
          break if value.nil?

          # process body
          varStore.set(@current_var, value)
          @mainChain.hop
        end
        # process final section
        hop_warn "START final chain #{self.to_s} (#{@finalChain})"
        @finalChain.hop

        hop_warn "FINISHED! #{self.to_s}\n-------------------------------"
        # write EOF to out stream
        do_yield(nil)
      rescue => e
        hop_warn "Exception in #{self.to_s} (#{@mainChain}: #{e}. "+e.backtrace.join("\t\n")
        raise
      end
    end

  end

  class TopStatement < Hopstance
    def self.createNewRetLineNum(parent,text,startLine)
      return TopStatement.new.createNewRetLineNum(parent,text,startLine)
    end

    def createNewRetLineNum(parent,text,startLine)
      # load arguments from config file
      Config.parmap.each do |par, val|
        varStore.addScalar par
        varStore.set par, (Param.cmd_arg_val(par) || val)
      end

      begin
        while true
          hopstance,startLine=Hopstance.createNewRetLineNum(self,text,startLine)
          @mainChain.add hopstance
        end
      rescue UnexpectedEOF
        return self
      end
    end

    def do_yield(hash)
      hop_warn hash.map {|key,val| "#{key} => #{val}"} .join("\n")
      hop_warn "\n"
    end

    def initialize
      super(nil)
    end

    def hop
      hop_warn "\n\n***********   START   *********************\n"
      super
      join_threads
      hop_warn   "\n***********   END     *********************\n"
      varStore.each{|var|
        hop_warn "VAR: #{var.to_s}"
      }
#      varStore.each_stream{|name, var|
#        hop_warn "Output Stream: #{name}"
#        while not (v=var.get).nil?
#          if v.class == Hash
#            hop_warn "-> #{v.to_csv}"
#          else
#            hop_warn "-> #{v}"
#          end
#        end
#      }

    end
  end
end
