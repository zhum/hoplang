require 'rubygems'
require 'cassandra/0.8'

module Hopsa

  include 'hop_varstore'
  require 'yaml'

  def load_program(text)
    Hopsa::Config.load
    return TopStatement.createNewRetLineNum(nil,text,0)
  end

  class HopPipe
    def get
      begin
#        warn "PIPE: #{@buffer[0]}"
        return @buffer.shift
      rescue
#        warn "PIPE IS NIL"
        return nil
      end
    end

    def put(value)
      @buffer ||= Array.new
      @buffer.push(value)
    end

    def empty?
      return nil if @buffer.nil?
      return @buffer.empty?
    end

    def to_s
      "#HopPipe: #{@buffer.size} inside."
    end
  end

  class HopChain

    def initialize(executor)
      @executor=executor
      @chain=Array.new
    end

    def add(element)
      @chain.push element
    end

    def hop
      @chain.each {|el| el.hop}
    end

    def to_s
      "#HopChain(#{@chain.size})"
    end
  end

  class HopExpression
    OPERATIONS=['+','-','*','/','%']

    def initialize(stack)
      @expr=stack
    end

    def self.line2expr(line)
      rest=line.strip
      stack=Array.new
      while rest != '' do;
        start,delimiter,rest=rest.partition(/\s+/)
        next if start == ''

        # operation?
        if OPERATIONS.include? start
          stack.push HopExprOp.new(start)
          next
        end

        # digit constant?
        if start=~/^\d+$/
          stack.push start
          next
        end

        # string constant?
        if start[0,1]=='"'
          if(fin=(start =~ /[^\\]\"/))              #]/
            stack.push start[1..fin]
          elsif start[1,1]=='"'
            stack.push ''
          else
            raise SyntaxError(l,"No string end found")
          end
          next
        end

        # variable?
        if start[0,1] =~ /\w/
          stack.push HopExprVar.new(start)
          next
        end

        # not processible...
        return HopExpression.new(stack),start+delimiter+rest

      end # while
      return HopExpression.new(stack),''
    end # ~line2expr

    # evaluate expression in Executor context
    def evaluate(ex)
      @stack=[]
      @expr.each do |el|
        case el
        when HopExprVar
          # evaluate variable
          var,dot,field=el.value.partition('.')
          if field==''
            # scalar
            val=VarStor.get(ex,el.value)
          else
            # cortege field
            begin
              val=VarStor.get(ex,var)[field]
            rescue
              warn ">> Opppps: #{var}.#{field}"
              nil
            end
          end
          @stack.push val

        when Numeric, String
          # constant
          @stack.push el

        when HopExprOp
          case el.value
          when '+'
            a1=@stack.pop
            a2=@stack.pop
            warn ">>PLUS: #{a1},#{a2}"
            raise SyntaxError if a2.nil?
            @stack.push a1.to_f+a2.to_f
          when '*'
            a1=@stack.pop
            a2=@stack.pop
            raise SyntaxError if a2.nil?
            @stack.push a1.to_f*a2.to_f
          when '-'
            a1=@stack.pop
            a2=@stack.pop
            warn ">>MINUS: #{a1},#{a2}"
            raise SyntaxError if a2.nil?
            @stack.push a2.to_f-a1.to_f
          when '/'
            a1=@stack.pop
            a2=@stack.pop
            raise SyntaxError if a2.nil?
            @stack.push a2.to_f/a1.to_f
          when '%'
            a1=@stack.pop
            a2=@stack.pop
            raise SyntaxError if a2.nil?
            @stack.push a2.to_f%a1.to_f
          else
            raise SyntaxError
          end
        end #~case
      end # ~each expression
      raise SyntaxError.new(@expr.to_s+' ('+@stack.to_s+')') if @stack.size>1

      return @stack.pop
    end

  end

  class HopExprVar
    attr :value

    def initialize(str)
      @value=str
    end

  end

  class HopExprOp
    attr :value

    def initialize(str)
      @value=str
    end

  end

  class Statement
  #  @input
  #  @output
  #  @finished
  #  @id

    attr_accessor :parent, :hopid
    @@globalId=0

    def self.nextId
      @@globalId+=1
    end

    def connectInput(input)
      @input=input
    end

    def connectOutput(output)
      @output=output
    end

    # parent = top block
    def initialize(parent=nil)
      warn ">>Statement #{parent.class.to_s}:#{self.class.to_s}"
      @parent=parent
      @finished=false
      @started=false
      @input=nil
      @finalChain=HopChain.new(self)
      @mainChain=HopChain.new(self)
      @hopid=Hopstance.nextId
    end

    # read next line and process it...
    #TODO !!!!!!!!!!!!! Add field names !!!!!!!!!!!!!
    def hop
      @mainChain.hop

    end

    # creates new Hopstance and returns it and next text line
    # ret: Hopstance,newStartLine
    def self.createNewRetLineNum(parent,text,startLine)
      startLine -=1
      while (true)
        startLine+=1
        line,startLine=Statement.nextLine(text,startLine)

        raise UnexpectedEOF if line.nil?
        case line
          # comment
        when /^#/, /^$/
          warn "Comment #{line}\n"
          redo

#!! simplify regexp
          # each
        when /^((\S+)\s*=\s*)?each\s+(\S+)(\s+where\s+(.*))?/
          return EachHopstance.createNewRetLineNum(parent, text, startLine)

#!! simplify regexp
          # group by
        when /^((\S+)\s*=\s*)?group\s+(\S+)\s+by\s+(\S+)(\s+where\s+(.*))?/
          return GroupHopstance.createNewRetLineNum(parent, text, startLine)

          # while cycle
        when /^\s*while\s+/
          return WhileHopstance.createNewRetLineNum(parent, text, startLine)

          # yield
        when /^yield\s+/
          return YieldStatement.createNewRetLineNum(parent, text, startLine)

          # scalar variable
        when /^scalar\s+(\S+)/
          # add new var in store
          VarStor.addScalar(parent, $1)
          redo

          # cortege variable
        when /^data\s+(\S+)/
          # add new var in store
          VarStor.addCortege(parent, $1)
          redo

          # let
        when /^(\S+)\s*=\s*(.)/
          return LetStatement.createNewRetLineNum(parent, text, startLine)

          # ooops....
        else
          raise SyntaxError.new #(line)
        end # case
      end
    end  # ~createNewRetLineNum

    def do_yield(hash)
      @parent.do_yield(hash)
    end

    def self.nextLine(text,pos)
      return nil,pos if text[pos].nil?
      while text[pos].match /\s*#/
        pos+=1
      end
      return text[pos].strip,pos
    end
  end


  class LetStatement < Statement
    def self.createNewRetLineNum(parent,text,startLine)

      line,startLine=nextLine(text,startLine)
      line =~ /^(\S+)\s*=\s*(.*)/
      expression,* = HopExpression.line2expr($2)
      ret = LetStatement.new parent, $1, expression
      return ret,startLine+1
    end

    def initialize(parent,var,expr)
      super(parent)
      @varname=var
      @expression=expr
    end

    def hop
      #!!!!!!!!!!!!!!!!TODO!!!!!!!!!!!!!!!!!!
      #!!!!!! scalar/cortege !!!!!!!!!!!!!!!!

      value=@expression.evaluate(@parent)
      VarStor.set(@parent, @varname, value)
    end

  end

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
        warn "VAR: #{var.to_s}\n"
      }
      VarStor.each_stream(self){|name, var|
        warn "Output Stream: #{name}\n"
        while(v=var.get)
          warn "-> #{v}\n"
        end
      }

    end
  end

  class YieldStatement < Statement
    def initialize(parent)
      @parent=parent
      @id=Hopstance.nextId
      @started=false
    end

    def self.createNewRetLineNum(parent,text,pos)
      return YieldStatement.new(parent).createNewRetLineNum(text,pos)
    end

    def createNewRetLineNum(text,pos)
      line,pos=Statement.nextLine(text,pos)
      field_num=1
      @fields=Hash.new

      raise UnexpectedEOF if line.nil?
      raise (SyntaxError) if(not line.match /^yield(\s*(.*))/)

      ret=$2
      while not ret.nil?;
        expr,ret = HopExpression.line2expr(ret)
        ret.match /^(=>\s*(\S+))?(.*)/
        unless $1.nil?
          # named field
          field_name=$2
        else
          # generate field name
          field_name="field_#{field_num}"
          field_num+=1
        end
        @fields[field_name]=expr

        ret=$3
        # remove separators...
        unless ret.nil?
          ret.match /^\s*,(.*)/
          ret=$1
        end
      end

      return self,pos+1
    end

    def hop
      ret={}
      @fields.map {|key,val| ret[key] = val.evaluate(self)}
      @parent.do_yield(ret)
    end

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
      elsif(type=='Cassandra') then
        hopstance=CassandraHopstance.new(parent)
      elsif(type=='split') then
        i=1
        types_list=Array.new
        while name=Config["n_#{i}_#{source}"] do
          types_list << {:n => i, :name => name}
          i+=1
        end
        hopstance=SplitEachHopstance.new(parent, types_list)
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
      @streamvar,@current_var=streamvar,current_var
      @source,@where=source,where

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
        warn ">>#{line}<<\n"
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
      warn "START (#{@mainChain})\n"
      while self.readSource
        # process body
        @mainChain.hop
      end
      # process final section
      warn "FINAL\n"
      @finalChain.hop

      warn "FINISHED!\n-------------------------------\n"
      while false #val=outPipe.get
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

  # DUMMY DATABASE ACCESS CLASS
  class MyDatabaseEachHopstance <EachHopstance
    # read next source line and write it into @source_var
    def readSource
      super
    end

  end

  class CassandraHopstance < EachHopstance

    def init(text,pos,streamvar,current_var,source,where)
      @address = '127.0.0.1:9160'
      @keyspace = 'hopsa'
      @column_family = :tasks_cheb
      @next_key = nil
      @end_of_stream = false
      # for test purposes only
      @max_items = 100
      @items_read = 0

      newStartLine = super(text,pos,streamvar,current_var,source,where)
      @cassandra = Cassandra.new('hopsa', 'localhost:9160')
      @enumerator = nil
      newStartLine
    end

    def readSource
      if @enumerator.nil?
        @enumerator = @cassandra.to_enum(:each, @column_family)
      end
      kv = nil
      begin
        kv = @enumerator.next
        @items_read += 1
      rescue StopIteration
        puts "finished iteration"
      end
      if !kv.nil?
        k,v=kv[0],kv[1]
        value = {'key' => k}.merge(v)
        value = nil if @items_read > @max_items
      end
      VarStor.set(self, @current_var, value)
    end
  end
  # Read several sources...
  class SplitEachHopstance <EachHopstance

    def initialize(parent, sources)
      super(parent)
      warn "SPLIT #{sources.size}"
      @sources=sources
    end

    def init(text,pos,streamvar,current_var,source,where)
      @hopsources=Array.new
      @streamvar,@current_var,@source=streamvar,current_var,source
      pos2=0

      @sources.each_with_index{|s,i|

        # deep clone...
        text_s=Marshal.load(Marshal.dump(text))

        #change 'each' statement...
        if streamvar=='' then
          text_s[pos]=''
        else
          text_s[pos]="#{streamvar}__#{i}="
        end
        text_s[pos]+="each #{current_var} in #{s[:name]}"
        text_s[pos]+=" where #{where}" if where !=''

        hopstance,pos2=EachHopstance.createNewRetLineNum(self,text_s,pos)
        @hopsources << hopstance
      }
      @current_source=-1
      return self,pos2+1
    end

#    def hop
#      warn "SplitHOP"
#    end

    # read next source line and write it into @source_var
    def readSource
      saved_source=@current_source

      begin
        @current_source+=1
        @current_source=0 if @current_source>=@hopsources.size

#        warn "->RRRRRRRRRRRRRRRRRRRRRR #{@hopsources[@current_source]}"

        #!!!! Must be deleted on thread version!!!
        @hopsources[@current_source].hop

#        warn "<-RRRRRRRRRRRRR #{@current_source}/#{@current_var}: #{@hopsources[@current_source]}(#{@hopsources[@current_source].streamvar})"
        if VarStor.canRead?(@hopsources[@current_source],
                            @hopsources[@current_source].streamvar) then
          value=VarStor.get(@hopsources[@current_source],
                            @hopsources[@current_source].streamvar)
          #@outPipe.put value
          VarStor.set(self, @streamvar, value)
#          warn "R_R #{value}"
          return value
        end
#        warn "RR #{saved_source} #{@current_source}"
      end while saved_source!=@current_source
      return nil
    end
  end

  class Config
    CONFIG_FILE='./hopsa.conf'
#    @data=Hash.new

    class << self
      def load
        @data=YAML.load(File.open(CONFIG_FILE, "r"))
        warn "YAML: #{@data}"
#        File.open(CONFIG_FILE,"r") do |file|
#          file.each {|line|
#            line.strip!
#            line =~ /([^= ]+)\s*=\s*(.*)/
#            warn "CONF: '#{$1}' = '#{$2}' (#{line})"
#            @data[$1]=$2
#          }
#        end
      end

      def [](key)
        begin
          warn "CONFIG: #{key}=#{@data[key]}"
          return @data[key]
        rescue
          warn "Warning: config key '#{key}' not found"
          return nil
        end
      end

      def varmap
#        warn ">>>>>>>>> #{@data.keys}"
        return @data["varmap"]
      end
    end
  end

  class BadHop < StandardError
  end

  class UnexpectedEOF < StandardError
  end

  class SyntaxError < StandardError
  end

  class VarNotFound < StandardError
  end
=begin
=end
end

