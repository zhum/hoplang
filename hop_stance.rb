module Hopsa
  # Statement, which process stream.
  # So, it has inPipe, which is connected to previous Hopstance output.
  class Hopstance < Statement
    def initialize(parent,inPipe=nil)
      super(parent)
      @outPipe=HopPipe.new
      @inPipe=inPipe
    end

    attr_accessor :outPipe, :inPipe

  end

  class EachHopstance < Hopstance

    attr_reader :streamvar

    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless line =~ /^(\S+)\s*=\s*each\s+(\S+)\s+in\s+(\S+)(\s+where\s+(.*))?/
        raise SyntaxError.new(line)
      end

      streamvar,current_var,source,where=$1,$2,$3,$5

      cfg_entry = Config["db_type_#{source}"]
      src=Config.varmap[source]
      type=src.nil? ? nil : src['type']
      if(VarStor.testStream(parent, source)) then
        hopstance=StreamEachHopstance.new(parent)
#      elsif(Config["db_type_#{source}"]=='csv') then
      elsif(type=='csv') then
        hopstance=MyDatabaseEachHopstance.new(parent)
      elsif(type=='cassandra') then
        hopstance=CassandraHopstance.new parent, source
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

      VarStor.addCortege(hopstance, current_var)
      VarStor.addStream(parent, streamvar)

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
      warn "START main chain (#{@mainChain})"
      while self.readSource
        if @where_expr && !@where_expr.eval(self)
          puts @where_expr.eval(self)
          next
        end
        # process body
        @mainChain.hop
      end
      # process final section
      warn "START final chain (#{@finalChain})"
      @finalChain.hop

      warn "FINISHED!\n-------------------------------"
      while val=outPipe.get
        warn ":>> "
        warn val.map {|key,val| "#{key} => #{val}"} .join("; ")
        warn "\n"
      end
    end

    def do_yield(hash)
      # push data into out pipe
      VarStor.set(self,@streamvar,hash)
    end

    # read next source line and write it into @source_var
    def readSource
      if @source_in.nil?
        @source_in = open @source
        # fields titles
        head=@source_in.readline.strip
        @heads=head.split /\s*,\s*/
      end

      begin
        line=@source_in.readline.strip
        datas=line.split /\s*,\s*/

        i=0
        value={}
        @heads.each {|h|
          value[h]=datas[i]
          i+=1
        }
        # now store variable!
        VarStor.set(self, @current_var, value)
      rescue EOFError
        return nil
      end
        line
    end
  end

  class StreamEachHopstance <EachHopstance
    # read next source line and write it into @source_var
    def readSource
      value=VarStor.get(self,@source)
      VarStor.set(self, @current_var, value)
    end
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
      print hash.map {|key,val| "#{key} => #{val}"} .join("\n")
      print "\n"
    end

    def initialize
      super(nil,HopPipe.new)
    end

    def hop
      super
      VarStor.each(self){|var|
        warn "VAR: #{var.to_s}"
      }
      VarStor.each_stream(self){|name, var|
        warn "Output Stream: #{name}"
        while(v=var.get)     
          if v.class == Hash
            warn "-> #{v.to_csv}"
          else
            warn "-> #{v}"
          end
        end
      }

    end
  end
end
