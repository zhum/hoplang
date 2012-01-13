module Hopsa
  class Statement

    attr_accessor :parent, :hopid

    @@globalId=0

    def self.nextId
      @@globalId+=1
    end

    def varStore
      parent.varStore
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
        when /^\s*#/, /^$/
          warn "Comment #{line.chomp}"
          redo

#!! simplify regexp
          # each
        when /^((\S+)\s*=\s*)?each\s+(\S+)(\s+where\s+(.*))?/
          return EachHopstance.createNewRetLineNum(parent, text, startLine)

        when /^print\s+(\S+)/
          return PrintEachHopstance.createNewRetLineNum(parent, text, startLine)

        when /^debug\s+(\S+)/
          return DebugStatement.createNewRetLineNum(parent, text, startLine)

          # sequential each
        when /^((\S+)\s*=\s*)?seq\s+(\S+)(\s+where\s+(.*))?/
          return EachHopstance.createNewRetLineNum(parent, text, startLine)

#!! simplify regexp
          # group by
        when /^((\S+)\s*=\s*)?group\s+(\S+)\s+by\s+(\S+)(\s+where\s+(.*))?/
          return GroupHopstance.createNewRetLineNum(parent, text, startLine)

          # while loop
        when /^\s*while\s+/
          return WhileStatement.createNewRetLineNum(parent, text, startLine)

          # if-else statement
        when /^\s*if\s+/
          return IfStatement.createNewRetLineNum(parent, text, startLine)

          # yield
        when /^\s*yield\s+/
          #puts 'matched yield statement'
          return YieldStatement.createNewRetLineNum(parent, text, startLine)

          # scalar variable
          # sevaral comma-separated variable names allowed
        when /^var\s+(\S.*)/
          $1.split(',').each do |vname|
            # add new var in store
            parent.varStore.addScalar vname.strip
          end
          redo

          # removed zhumcode begin
          # cortege variable
          # TODO: deprecate, so that it it the same as scalar variable
        #when /^data\s+(\S+)/
          # add new var in store
          #VarStor.addCortege(parent, $1)
         # redo
         # removed zhumcode end

          # let
        when /^(\S+)\s*=\s*(.)/
          # puts 'creating let statement'
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

  # represents if ... [ else ... ] end statement
  class IfStatement < Statement
    def if_chain
      @mainChain
    end
    def else_chain
      @finalChain
    end
    def self.createNewRetLineNum(parent,text,startLine)
      return IfStatement.new(parent).createNewRetLineNum(parent,text,startLine)
    end
    def createNewRetLineNum(parent,text,startLine)
      line,pos = Statement.nextLine(text,startLine);
      raise SyntaxError if !line.match /\s*if\s+(.*)/
      @cond_expr = HopExpr.parse_cond $1
      warn @cond_expr.inspect
      pos += 1
      cur_chain = if_chain
      while true
        # second while for processing after switching to else chain
        begin
          while true
            # it may be better to pass self as parent to nested statements
            # and hopstances. However, currently no variable declarations are
            # allowed in while, that's why we pass parent
            hopstance,pos = Hopstance.createNewRetLineNum(parent,text,pos)
            cur_chain.add hopstance
          end
        rescue SyntaxError
          line, pos = Statement.nextLine(text, pos)
          if line == 'else'
            raise if cur_chain == else_chain
            cur_chain = else_chain
            pos += 1
          elsif line == 'end'
            return self, pos + 1
          else
            raise
          end
        end # begin
      end # outer while true
      # must not reach here
    end # createNewRetLineNum

    def hop
      if @cond_expr.eval(@parent)
        if_chain.hop
      else
        else_chain.hop
      end
    end
  end # IfStatement

  # represents while statement
  class WhileStatement < Statement
    def self.createNewRetLineNum(parent,text,startLine)
      return WhileStatement.new(parent).createNewRetLineNum(parent,text,startLine)
    end

    def createNewRetLineNum(parent,text,startLine)
      line,pos = Statement.nextLine(text,startLine);
      raise SyntaxError if !line.match /\s*while\s+(.*)/
      @cond_expr = HopExpr.parse_cond $1
      warn @cond_expr.inspect
      pos += 1
      begin
        while true
          # it may be better to pass self as parent to nested statements
          # and hopstances. However, currently no variable declarations are
          # allowed in while, that's why we pass parent
          hopstance,pos = Hopstance.createNewRetLineNum(parent,text,pos)
          @mainChain.add hopstance
        end
      rescue SyntaxError
        line,pos = Statement.nextLine(text, pos)
        if line == 'end'
          return self, pos + 1
        else
          raise
        end
      end # begin
      # must not reach here
    end # createNewRetLineNum

    def hop
      while @cond_expr.eval(@parent)
        @mainChain.hop
      end
    end
  end # WhileStatement

  class LetStatement < Statement
    def self.createNewRetLineNum(parent,text,startLine)

      line,startLine=nextLine(text,startLine)
      #line =~ /^(\S+)\s*=\s*(.*)/
      #expression,* = HopExpression.line2expr($2)
      expression = HopExpr.parse(line)
      #puts expression.inspect
      #ret = LetStatement.new parent, $1, expression
      ret = LetStatement.new parent, expression
      return ret,startLine+1
    end

    def initialize(parent, expr)
      super(parent)
      # @varname=var
      @expression=expr
    end

    def hop
      #!!!!!!!!!!!!!!!!TODO!!!!!!!!!!!!!!!!!!
      #!!!!!! scalar/cortege !!!!!!!!!!!!!!!!
      # TODO: support expression lists for tuple assignments
      # right now, it is not implemented

      #value=@expression.evaluate(@parent)
      #VarStor.set(@parent, @varname, value)
      @expression.eval @parent
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
      #puts 'creating yield statement'
      line,pos=Statement.nextLine(text,pos)
      field_num=1
      # maps names to expressions
      @fields=Hash.new

      raise UnexpectedEOF if line.nil?
      raise (SyntaxError) if(not line.match /^\s*yield(\s*(.*))/)

      # parse expressions
      #puts $2
      elist = HopExpr.parse_list $2
      #puts elist
      elist.each do |e|
        name = e.name
        if name == ''
          name = "field_#{field_num}"
        end
        field_num += 1
        @fields[name] = e
      end
      @fields['__hoplang_cols_order']=elist.map{|e| e.name}.join(',')

# removed zhumcode begin
      # ret=$2
      # while not ret.nil?;
      #   expr,ret = HopExpression.line2expr(ret)
      #   ret.match /^(=>\s*(\S+))?(.*)/
      #   unless $1.nil?
      #     # named field
      #     field_name=$2
      #   else
      #     # generate field name
      #     field_name="field_#{field_num}"
      #     field_num+=1
      #   end
      #   @fields[field_name]=expr

      #   ret=$3
      #   # remove separators...
      #   unless ret.nil?
      #     ret.match /^\s*,(.*)/
      #     ret=$1
      #   end
      # end
# removed zhumcode end

      return self,pos+1
    end

    def hop
      ret = {}
      @fields.map do |name, expr|
        ret[name] = expr.eval(self) unless name == '__hoplang_cols_order'
      end
      ret['__hoplang_cols_order'] = @fields['__hoplang_cols_order']
      @parent.do_yield(ret)
    end

  end


  # debug EXPR statement
  class DebugStatement < Statement
    def self.createNewRetLineNum(parent,text,startLine)
      return DebugStatement.new(parent).createNewRetLineNum(parent,text,startLine)
    end
    def createNewRetLineNum(parent,text,startLine)
      line,pos = Statement.nextLine(text,startLine);
      raise SyntaxError if !line.match /debug\s+(.*)/
      @line=startLine
      @expr = HopExpr.parse_cond $1
      warn "debug: #{@expr.inspect}"
      return self, pos + 1
    end # createNewRetLineNum

    def hop
      warn "DEBUG(#{@line}): #{@expr.eval(@parent)}"
    end
  end # DebugStatement
end
