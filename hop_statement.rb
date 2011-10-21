module Hopsa
  class Statement

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
        #warn "PROCESS #{text[startLine]}"
        startLine+=1
        line,startLine=Statement.nextLine(text,startLine)

        raise UnexpectedEOF if line.nil?
        case line
          # comment
        when /^#/, /^$/
          warn "Comment #{line.chomp}"
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

          # include
        when /^include (\S+)/
          text.delete_at(startLine) # no include clause now...
          include_file($~[1], text, startLine)
          redo

          # ooops....
        else
          warn "Cannot understand '#{startLine}: #{line}'"
          raise SyntaxError.new #(line)
        end # case
      end
    end  # ~createNewRetLineNum

    def self.include_file(file,txt,pos)
      warn "Include #{file}"
      IO.foreach(file) do |line|
          txt.insert(pos,line)
          pos+=1
      end
      warn "Included"
    end

    def do_yield(hash)
      @parent.do_yield(hash)
    end

    def self.nextLine(text,pos)
      return nil,pos if text[pos].nil?
      begin
        while text[pos].match(/\s*#/)
          pos+=1
        end
      rescue NoMethodError
        pos-=1
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
end

