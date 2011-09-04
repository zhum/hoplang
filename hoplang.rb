class BadHopError < StandardError
end

class UnexpectedEOFHopError < StandardError
end

class SyntaxErrHopError < StandardError
end

class VarNotFoundHopError < StandardError
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
    @chain.each {|element| element.hop}
  end
end

class Hopstance
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
    warn ">>HOPSTANCE #{parent}"
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
  def createNewRetLineNum(text,startLine)
    startLine -=1
    while (true)
      startLine+=1
      line=text[startLine]

      raise UnexpectedEOFHopError if line.nil?
      line=line.strip
      case line
        # comment
      when /^#/, /^$/
#        startLine+=1
        redo

        # each
      when /^((\S+)\s*=\s*)?each\s+(\S+)(\s+where\s+(.*))?/
        ret=EachHopstance.new(self)
        return ret.createNewRetLineNum(text, startLine)

        # group by
      when /^((\S+)\s*=\s*)?group\s+(\S+)\s+by\s+(\S+)(\s+where\s+(.*))?/
        ret=GroupHopstance.new(self)
        return ret.createNewRetLineNum(text, startLine)

        # while cycle
      when /^\s*while\s+/
        ret=WhileHopstance.new(self)
        return ret.createNewRetLineNum(text, startLine)

        # yield
      when /^yield(\s*(.*))/
        ret=YieldHopstance.new(self)
        return ret.createNewRetLineNum(text, startLine)

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
        ret=LetHopstance.new(self)
        return ret.createNewRetLineNum(text, startLine)

        # ooops....
      else
        raise SyntaxErrHopError.new #(line)
      end # case
    end
  end  # ~createNewRetLineNum

  def do_yield(hash)
    @parent.do_yield(hash)
  end
end

class TopHopstance < Hopstance
  def createNewRetLineNum(text,startLine)
    begin
      while true
        hopstance,startLine=super
        @mainChain.add hopstance
      end
    rescue UnexpectedEOFHopError
      return self
    end
  end

  def do_yield(hash)
    print hash.map {|key,val| "#{key} => #{val}"} .join("\n")
    print "\n"
  end
end


class LetHopstance <Hopstance
  def createNewRetLineNum(text,startLine)
    text[startLine] =~ /^(\S+)\s*=\s*(.*)/
    @varname=$1
    @expression,dummy=HopExpression.line2expr($2)
    return self,startLine+1
  end

  def hop
    #!!!!!!!!!!!!!!!!TODO!!!!!!!!!!!!!!!!!!
    #!!!!!! scalar/cortege !!!!!!!!!!!!!!!!

    value=@expression.evaluate(@parent)
    VarStor.setScalar(@parent, @varname, value)
  end

end

class VarStor

#  def initialize
    @scalarStore=Hash.new
    @cortegeStore=Hash.new
#  end

  def self.addScalar(ex,name)
    hopid=ex.hopid
    if @scalarStore[hopid].nil?
      @scalarStore[hopid]=Hash.new
    end

    @scalarStore[hopid][name]=''
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
      warn ">>SET: #{hopid} #{name}.#{key} = #{value}"
      @cortegeStore[hopid][name][key]=value
    }
  end

  private
  # where search (hash), executor, varname
  def self.searchIdForVar(store,ex,name)
    while not ex.nil? do;
#@@      warn ">>SEARCH #{name} (#{ex.hopid})"
      if not store[ex.hopid].nil?
        if not store[ex.hopid][name].nil?
          return ex.hopid
        end
      end
      ex=ex.parent
    end
    warn "SERARCH FAIL #{name}"
    raise VarNotFoundHopError.new(name)
  end

end


class YieldHopstance < Hopstance
  def initialize(parent)
    @parent=parent
    @id=Hopstance.nextId
    @started=false
  end

  def createNewRetLineNum(text,pos)
    line=text[pos]
    field_num=1
    @fields=Hash.new

    raise UnexpectedEOFHopError if line.nil?
    line=line.strip
    raise (SyntaxErrHopError) if(not line.match /^yield(\s*(.*))/)

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

  def createNewRetLineNum(text,pos)
    line=text[pos]

    raise UnexpectedEOFHopError if line.nil?
    line=line.strip
    unless line =~ /^(\S+)\s*=\s*each\s+(\S+)\s+in\s+(\S+)(\s+where\s+(.*))?/
      raise SyntaxErrHopError.new(line)
    end

    @streamvar,@current_var,@source,@where=$1,$2,$3,$5
    VarStor.addCortege(self, @streamvar)
    VarStor.addCortege(self, @current_var)

    pos+=1
    # now create execution chains for body and final sections
    begin
      while true
        hopstance,pos=super(text,pos)
        @mainChain.add hopstance
      end
    rescue SyntaxErrHopError
      line=text[pos]
      if line == 'final'
        # process final section!
        begin
          while true
            hopstance,pos=super(text,pos)
            @finalChain.add hopstance
          end
        rescue SyntaxErrHopError
          line=text[pos]
          if line == 'end'
            return self,pos+1
          end
        end
      elsif line == 'end'
        return self,pos+1
      end
    end
    raise SyntaxErrHopError.new(line)

  end

  def hop
    while self.readSource
      # process body
      @mainChain.hop
    end
    # process final section
    @finalChain.hop
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
      VarStor.setCortege(self, @current_var, value)
    rescue EOFError
      return nil
    end
      line
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
          raise SyntaxErrHopError(l,"No string end found")
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
          val=VarStor.getScalar(ex,el.value)
        else
          # cortege field
          begin
            val=VarStor.getCortege(ex,var)[field]
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
          raise SyntaxErrHopError if a2.nil?
          @stack.push a1.to_f+a2.to_f
        when '*'
          a1=@stack.pop
          a2=@stack.pop
          raise SyntaxErrHopError if a2.nil?
          @stack.push a1.to_f*a2.to_f
        when '-'
          a1=@stack.pop
          a2=@stack.pop
          warn ">>MINUS: #{a1},#{a2}"
          raise SyntaxErrHopError if a2.nil?
          @stack.push a2.to_f-a1.to_f
        when '/'
          a1=@stack.pop
          a2=@stack.pop
          raise SyntaxErrHopError if a2.nil?
          @stack.push a2.to_f/a1.to_f
        when '%'
          a1=@stack.pop
          a2=@stack.pop
          raise SyntaxErrHopError if a2.nil?
          @stack.push a2.to_f%a1.to_f
        else
          raise SyntaxErrHopError
        end
      end #~case
    end # ~each expression
    raise SyntaxErrHopError.new(@expr.to_s+' ('+@stack.to_s+')') if @stack.size>1

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

