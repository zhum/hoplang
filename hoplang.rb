module Hopsa
  class BadHop < StandardError
  end

  class UnexpectedEOF < StandardError
  end

  class SyntaxError < StandardError
  end

  class VarNotFound < StandardError
  end

  class HopPipe
    def get
      begin
        return @buffer.shift
      rescue
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

  end

  class VarStor

  #  def initialize
      @scalarStore=Hash.new
      @cortegeStore=Hash.new
      @streamStore=Hash.new
  #  end

    def self.addScalar(ex,name)
      hopid=ex.hopid
      warn "ADD_SCALAR: #{name} (#{hopid}/#{ex})\n"
      if @scalarStore[hopid].nil?
        @scalarStore[hopid]=Hash.new
      end

      @scalarStore[hopid][name]=''
    end

    def self.addStream(ex,name)
      hopid=ex.hopid
      if @streamStore[hopid].nil?
        @streamStore[hopid]=Hash.new
      end

      @streamStore[hopid][name]=HopPipe.new
    end

    def self.addCortege(ex,name)
      hopid=ex.hopid
      if @cortegeStore[hopid].nil?
        @cortegeStore[hopid]=Hash.new
      end

      @cortegeStore[hopid][name]={}
      warn ">>ADD #{name} (#{hopid})"
    end

    def self.getScalar(ex, name)
      hopid=searchIdForVar(@scalarStore,ex,name)
      warn ">>Read #{name} = #{@scalarStore[hopid][name]}"
      @scalarStore[hopid][name]
    end

    def self.getCortege(ex, name)
      hopid=searchIdForVar(@cortegeStore,ex,name)
      @cortegeStore[hopid][name]
    end

    def self.setScalar(ex, name, val)
      hopid=searchIdForVar(@scalarStore,ex,name)
      @scalarStore[hopid][name]=val
    end

    def self.setCortege(ex, name, val)
  #@@    warn ">>SET0: #{name} = #{val}"
      hopid=searchIdForVar(@cortegeStore,ex,name)
      val.each_pair{|key,value|
        warn ">>SET #{name}: #{hopid} #{name}.#{key} = #{value}"
        @cortegeStore[hopid][name][key]=value
      }
    end

    def self.getStream(ex, name)
      hopid=searchIdForVar(@streamStore,ex,name)
      @streamStore[hopid][name].get
    end

    def self.setScalar(ex, name, val)
      hopid=searchIdForVar(@streamStore,ex,name)
      @streamStore[hopid][name].put val
    end

    def self.set(ex, name, val)
      begin
        hopid=searchIdForVar(@streamStore,ex,name)
        @streamStore[hopid][name].put val
      rescue VarNotFound
        begin
          hopid=searchIdForVar(@cortegeStore,ex,name)
          @cortegeStore[hopid][name]=val
        rescue VarNotFound
          hopid=searchIdForVar(@scalarStore,ex,name)
          @scalarStore[hopid][name]=val
        end
      end
    end

    def self.get(ex, name)
      begin
        hopid=searchIdForVar(@streamStore,ex,name)
        return  @streamStore[hopid][name].get
      rescue VarNotFound
        begin
          hopid=searchIdForVar(@cortegeStore,ex,name)
          return @cortegeStore[hopid][name]
        rescue VarNotFound
          begin
            hopid=searchIdForVar(@scalarStore,ex,name)
#            warn "#{hopid}."
            return @scalarStore[hopid][name]
          rescue
            warn "Var not found: #{name} (#{hopid}/#{ex})"
            raise VarNotFound
          end
        end
      end
    end

    # variables iterator
    def self.each_scalar(ex, &block)
      begin
        @scalarStore[ex.hopid].each &block
      rescue
      end
    end

    # variables iterator
    def self.each_cortege(ex, &block)
      begin
        @cortegeStore[ex.hopid].each &block
      rescue
      end
    end

    # variables iterator
    def self.each_stream(ex, &block)
      begin
        @streamStore[ex.hopid].each &block
      rescue
      end
    end

    def self.each(ex, &block)
      each_stream(ex,&block)
      each_cortege(ex,&block)
      each_scalar(ex,&block)
    end

    def self.testStream(ex, name)
      begin
        hopid=searchIdForVar(@streamStore,ex,name)
        return true
      rescue VarNotFound
        return false
      end
    end

    private
    # where search (hash), executor, varname
    def self.searchIdForVar(store,ex,name)
      while not ex.nil? do;
        if not store[ex.hopid].nil?
#          warn "Trace: #{name} #{ex.hopid} = #{store[ex.hopid][name]} "
          if not store[ex.hopid][name].nil?
#            warn "YE!"
            return ex.hopid
          end
        end
        ex=ex.parent
      end
  #    warn "SEARCH FAIL #{name}"
      raise VarNotFound.new(name)
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
    def self.createNewRetLineNum(text,startLine)
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
          return EachHopstance.createNewRetLineNum(self, text, startLine)

#!! simplify regexp
          # group by
        when /^((\S+)\s*=\s*)?group\s+(\S+)\s+by\s+(\S+)(\s+where\s+(.*))?/
          return GroupHopstance.createNewRetLineNum(self, text, startLine)

          # while cycle
        when /^\s*while\s+/
          return WhileHopstance.createNewRetLineNum(self, text, startLine)

          # yield
        when /^yield\s+/
          return YieldStatement.createNewRetLineNum(self, text, startLine)

          # scalar variable
        when /^scalar\s+(\S+)/
          # add new var in store
          VarStor.addScalar(self, $1)
          redo

          # cortege variable
        when /^data\s+(\S+)/
          # add new var in store
          VarStor.addCortege(self, $1)
          redo

          # let
        when /^(\S+)\s*=\s*(.)/
          return LetStatement.createNewRetLineNum(self, text, startLine)

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
      ret=LetStatement.new parent
      text[startLine] =~ /^(\S+)\s*=\s*(.*)/
      ret.varname=$1
      ret.expression,dummy=HopExpression.line2expr($2)
      return ret,startLine+1
    end

    def hop
      #!!!!!!!!!!!!!!!!TODO!!!!!!!!!!!!!!!!!!
      #!!!!!! scalar/cortege !!!!!!!!!!!!!!!!

      value=@expression.evaluate(@parent)
      VarStor.set(@parent, @varname, value)
    end

    protected
    attr :variable, :expression
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
    def self.createNewRetLineNum(text,startLine)
      begin
        while true
          hopstance,startLine=super
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

    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless line =~ /^(\S+)\s*=\s*each\s+(\S+)\s+in\s+(\S+)(\s+where\s+(.*))?/
        raise SyntaxError.new(line)
      end

      streamvar,current_var,source,where=$1,$2,$3,$5

      if(VarStor.testStream(parent, current_var)) then
        hopstance=StreamEachHopstance.new(parent)
      else
        warn "NEW!"
        hopstance=EachHopstance.new(parent)
      end

      VarStor.addCortege(hopstance, current_var)
      VarStor.addStream(parent, streamvar)

      return hopstance.init(text,pos,streamvar,current_var,source,where)
    end

    def init(text,pos,streamvar,current_var,source,where)
      @streamvar,@current_var=streamvar,current_var
      @source,@where=source,where

      pos+=1
      warn ":: #{text[pos]}"
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
      print "START\n"
      while self.readSource
        # process body
        @mainChain.hop
      end
      # process final section
      print "FINAL\n"
      @finalChain.hop

      print "FINISHED!\n-------------------------------\n"
      while false #val=outPipe.get
        print ":>> "
        print val.map {|key,val| "#{key} => #{val}"} .join("; ")
        print "\n"
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

end

