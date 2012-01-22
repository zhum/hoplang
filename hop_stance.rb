class String
  def csv_escape
    gsub('"','\\"')
    if(self =~ /,/)
      return '"'+self+'"'
    end
    self
  end

  def to_class
    Object.const_get(self)
  end
end

module Hopsa
  # Statement, which process stream.
  # So, it has inPipe, which is connected to previous Hopstance output.
  class Hopstance < Statement
    def initialize(parent,inPipe=nil)
      super(parent)

      @varStore=VarStore.new(self)
    end

    attr_accessor :outPipe, :inPipe, :varStore

    def join_threads
      @@threads.each do |t|
        warn "T: #{t} #{t.status}"
        t.join
      end
      @@threads=[]
    end

    def new_thread &block

      @@threads ||= []
      @@threads.push(Thread.new(&block))
    end
  end

  class EachHopstance < Hopstance

    attr_reader :streamvar

    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless((line =~
      /^(\S+)\s*=\s*each\s+(\S+)\s+in\s+(\S+)(\s+where\s+(.*))?/) || (line =~ /^(\S+)\s*=\s*seq\s+(\S+)\s+in\s+(\S+)(\s+where\s+(.*))?/))

        raise SyntaxError.new(line)
      end

      streamvar,current_var,source,where=$1,$2,$3,$5

      cfg_entry = Config["db_type_#{source}"]
      src=Config.varmap[source]
      type=src.nil? ? nil : src['type']
      if(parent.varStore.testStream(source)) then
        hopstance=StreamEachHopstance.new(parent)
#      elsif(Config["db_type_#{source}"]=='csv') then
      elsif(type=='csv') then
        hopstance=MyDatabaseEachHopstance.new(parent,source)
#      elsif(type=='cassandra') then
#        hopstance=CassandraHopstance.new parent, source
#      elsif(type=='mongo') then
#        hopstance=MongoHopstance.new parent, source
      elsif(@@hoplang_databases.include? type)
        typename=(type.capitalize+'Hopstance').to_class
        hopstance = typename.new parent, source, current_var, where
      elsif(type=='split') then
        i=1
        types_list=Array.new
        while name=Config["n_#{i}_#{source}"] do
          types_list << {:n => i, :name => name}
          i+=1
        end
        hopstance=SplitEachHopstance.new(parent, types_list)
      elsif(not type.nil?) then
        begin
          hopstance=Object.const_get(type+'Hopstance').new(parent)
        rescue NameError
          warn "No such driver: #{type}!"
          hopstance=EachHopstance.new(parent)
        end
      else
        warn "DEFAULT Each"
        hopstance=EachHopstance.new(parent)
      end

      hopstance.varStore.addScalar(current_var)
      parent.varStore.addStream(streamvar)
      hopstance.varStore.copyStreamFromParent(streamvar,parent.varStore)

      warn "ADDED STREAM: #{parent.varStore.object_id} #{streamvar}"

      return hopstance.init(text,pos,streamvar,current_var,source,where)
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
      warn ":: #{text[pos]}"
      warn "EACH: #{streamvar},#{current_var},#{source},#{where}"
      # now create execution chains for body and final sections
      begin
        while true
          statement,pos=Statement.createNewRetLineNum(self,text,pos)
          @mainChain.add statement
        end
      rescue SyntaxError
        line,pos=Statement.nextLine(text,pos)
        warn ">>#{line}<<"
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
      raise SyntaxError.new(line)
    end

    def hop
      warn "START main chain #{@streamvar} <- #{@source} (#{@mainChain})"
      new_thread do
        begin
          while not (self.readSource).nil?
            if @where_expr && !@where_expr.eval(self)
              #puts @where_expr.eval(self)
              next
            end
            # process body
            @mainChain.hop
          end
          # process final section
          warn "START final chain (#{@finalChain})"
          @finalChain.hop

          warn "FINISHED!\n-------------------------------"
          # write EOF to out stream
          do_yield(nil)
#          while not (val=outPipe.get).nil?
#            warn ":>> "
#            warn val.map {|key,val| "#{key} => #{val}"} .join("; ")
#            warn "\n"
#          end
        rescue => e
          warn "Exception in #{@streamvar} <- #{@source} (#{@mainChain}: #{e}. #{e.backtrace}"
        end
      end #~Thread
    end

    def do_yield(hash)
      # push data into out pipe
      varStore.set(@streamvar,hash)
    end

    # read next source line and write it into @source_var
    def readSource
      if @source_in.nil?
        @source_in = open @source
        # fields titles
        head=@source_in.readline.strip
        @heads=head.split(/\s*,\s*/)
      end

      begin
        line=@source_in.readline.strip
        datas=line.split(/\s*,\s*/)

        i=0
        value={}
        @heads.each {|h|
          value[h]=datas[i]
          i+=1
        }
        # now store variable!
        varStore.set(@current_var, value)
      rescue EOFError
        warn "EOF.....\n"
        varStore.set(@current_var, nil)
        return nil
      end
        line
    end
  end

  class StreamEachHopstance < EachHopstance
    # read next source line and write it into @source_var
    def readSource
      value=varStore.get(@source)
      varStore.set(@current_var, value)
      value
    end
  end

  class PrintEachHopstance < EachHopstance
    # read next source line and write it into @source_var
    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless(line =~ /print\s+(\S+)/)
        raise SyntaxError.new(line)
      end

      hopstance=PrintEachHopstance.new(parent)
      return hopstance.init($1),pos+1
    end

    def init(source)
      @source=source
      self
    end

    def hop
      new_thread do
        while not (self.readSource).nil?
        end
      end
    end

    def readSource
      value=varStore.get(@source)
      return nil if value.nil?
      if(not Config['local'].nil? and
         Config['local']['out_format'] == 'csv')
        if @out_heads.nil?
          @out_heads=value['__hoplang_cols_order'].split(/,/)
          # print header
          puts value['__hoplang_cols_order']
        end

        puts @out_heads.map {|key| value[key].to_s.csv_escape}.join(',')
      else
        puts "OUT>>#{value.inspect}"
      end
      value
    end
  end

  # a special hopstance which processes elements in strict sequential order
  # can be used, for instance, for easy implementation of accumulators
  # currently, just an empty class
  class SeqHopstance < StreamEachHopstance
  end

  class TopStatement < Hopstance
    def self.createNewRetLineNum(parent,text,startLine)
      return TopStatement.new.createNewRetLineNum(parent,text,startLine)
    end

    def createNewRetLineNum(parent,text,startLine)
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
      warn hash.map {|key,val| "#{key} => #{val}"} .join("\n")
      warn "\n"
    end

    def initialize
      super(nil,HopPipe.new)
    end

    def hop
      warn "\n\n***********   START   *********************\n"
      super
      join_threads
      warn "\n***********   END     *********************\n"
      varStore.each{|var|
        warn "VAR: #{var.to_s}"
      }
#      varStore.each_stream{|name, var|
#        warn "Output Stream: #{name}"
#        while not (v=var.get).nil?
#          if v.class == Hash
#            warn "-> #{v.to_csv}"
#          else
#            warn "-> #{v}"
#          end
#        end
#      }

    end
  end
end
