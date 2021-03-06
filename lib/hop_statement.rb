module Hopsa
  class Statement

    attr_accessor :parent, :hopid

    @@globalId=0
    @@current_line=0

    def self.nextId
      @@globalId+=1
    end

    def self.current_line
      @@current_line
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
      hop_warn ">>Statement #{parent.class.to_s} => #{self.class.to_s}"
      @parent=parent
      @finished=false
      @started=false
      @input=nil
      # init chain is executed before main hopstance body, and mainly contains
      # initializers
      @initChain=HopChain.new self
      @finalChain=HopChain.new self
      @mainChain=HopChain.new self
      @hopid=Hopstance.nextId
    end

    # extracts aggregates from expressions in the statement, and replaces
    # aggregate expressions with new expressions. The returned value is the
    # dictionary part from the result of extract_agg for expressions
    def extract_agg!      
      # nothing to do
      {}
    end

    # read next line and process it...
    #TODO !!!!!!!!!!!!! Add field names !!!!!!!!!!!!!
    def hop
      @mainChain.hop

    end

    def executor=(ex)
      @parent=ex
      #hop_warn "EX=> #{self.inspect} -> #{ex.inspect}"
    end

    def hop_clone
      hop_warn "No clone for #{self.to_s}"
      self
    end

    def dump_parents
      parent=self
      begin
        until parent.nil?
          hop_warn "^^ #{parent.to_s}"
          parent=parent.parent
        end
      rescue => e
        hop_warn "^^^^^ exception: #{e.message}"
      end
    end

    # creates new Hopstance and returns it and next text line
    # ret: Hopstance,newStartLine
    def self.createNewRetLineNum(parent,text,startLine)
      @line=startLine
      startLine -=1
      while (true)
        #hop_warn "PROCESS #{text[startLine]}"
        startLine+=1
        line,startLine=Statement.nextLine(text,startLine)

        raise UnexpectedEOF if line.nil?
        case line
          # comment
        when /^\s*#/, /^$/
          hop_warn "Comment #{line.chomp}"
          redo

#!! simplify regexp
          # each
        when /^((\S+)\s*=\s*)?each\s+(\S+)(\s+where\s+(.*))?/
          return EachHopstance.createNewRetLineNum(parent, text, startLine)

        when /^((\S+)\s*=\s*)?top\s+(.+)\s+(\S+)\s+in\s+(\S+)\s+by\s+(.*)(\s+where\s+(.*))?/
          return TopEachHopstance.createNewRetLineNum(parent, text, startLine)

        when /^\s*(\S+)\s*=\s*sort\s+(\S+)\s+in\s+(\S+)\s+by\s+(.*)(\s+(\S+)\s+where\s+(.*))?/
          return SortEachHopstance.createNewRetLineNum(parent, text, startLine)

        when /^((\S+)\s*=\s*)?bottom\s+(.+)\s+(\S+)\s+in\s+(\S+)\s+by\s+(.*)(\s+where\s+(.*))?/
          return BottomEachHopstance.createNewRetLineNum(parent, text, startLine)

        when /^(\S+)\s*=\s*union\s+(.+)/
          return UnionHopstance.createNewRetLineNum(parent, text, startLine)
          
        when /^print(\(\s*\S*\s*\))?\s*(.*)/
          return PrintEachHopstance.createNewRetLineNum(parent, text, startLine)

        when /^debug\s+(\S+)/
          return DebugStatement.createNewRetLineNum(parent, text, startLine)

          # sequential each
        when /^((\S+)\s*=\s*)?seq\s+(\S+)(\s+where\s+(.*))?/
          return EachHopstance.createNewRetLineNum(parent, text, startLine)

#!! simplify regexp
          # group by

        when /^((\S+)\s*=\s*)?group\s+(\S+)\s+by\s+(.+)\s+in\s+(\S+)(\s+where\s+(.*))?/
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

          # query parameter
        when /^param\s+(\w+)\s*(?:=\s*(\S+))/
          name=$~[1]
          val=$~[2]
          if val[0] == "'"
            val.gsub!(/^\'|\'$/, '')
          elsif  val[0] == '"'
            val.gsub!(/^\"|\"$/, '')
          end
          if Config.varmap.has_key? name
            # just update value, if any
            parent.varStore.set(name, val) if val && !Param.cmd_arg_val(name)
          else
            # add variable and value
            parent.varStore.addScalar name
            parent.varStore.set name, Param.cmd_arg_val(name) || val
          end
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
          raise SyntaxError.new "Cannot understand '#{startLine}: #{line}'"
        end # case
      end
    end  # ~createNewRetLineNum

    def self.include_file(file,txt,pos)
      hop_warn "Include #{file}"
      IO.foreach(file) do |line|
          txt.insert(pos,line)
          pos+=1
      end
      hop_warn "Included"
    end

    def do_yield(hash)
      @parent.do_yield(hash)
    end

    def self.nextLine(text,pos)
      current_line=pos
      return nil,pos if text[pos].nil?
      begin
        while text[pos].match(/\s*#/)
          pos+=1
        end
      rescue NoMethodError
        pos-=1
      end
      current_line=pos
      return text[pos].strip,pos
    end

    private

    def current_line=(line)
      @@current_line=line
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

    def initialize(parent,main=nil,final=nil,cond=nil)
      super(parent)
      @mainChain=(main.nil? ? HopChain.new(self) : main)
      @finalChain=(final.nil? ? HopChain.new(self) : final)
      @cond_expr=cond
    end

    def executor=(ex)
      super
      @mainChain.executor=ex
      @finalChain.executor=ex
    end

    def hop_clone
      return IfStatement.new(@parent,@mainChain.hop_clone,
                             @finalChain.hop_clone, @cond_expr.hop_clone)
    end

    def self.createNewRetLineNum(parent,text,startLine)
      return IfStatement.new(parent).createNewRetLineNum(parent,text,startLine)
    end
    def createNewRetLineNum(parent,text,startLine)
      line,pos = Statement.nextLine(text,startLine);
      @line=startLine
      raise SyntaxError if !line.match /\s*if\s+(.*)/
      @cond_expr = HopExpr.parse_cond $1
      hop_warn @cond_expr.inspect
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

    def initialize(parent,main=nil,cond=nil)
      super(parent)
      @mainChain=(main.nil? ? HopChain.new(self) : main)
      @cond_expr=cond
    end

    def hop_clone
      return WhileStatement.new(@parent,@mainChain.hop_clone,@cond_expr.hop_clone)
    end

    def executor=(ex)
      super
      @mainChain.executor=ex
    end

    def createNewRetLineNum(parent,text,startLine)
      line,pos = Statement.nextLine(text,startLine);
      @line=startLine
      raise SyntaxError if !line.match /\s*while\s+(.*)/
      @cond_expr = HopExpr.parse_cond $1
      hop_warn @cond_expr.inspect
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
    def self.createNewRetLineNum(parent,text,startLine=nil)

      line,startLine=nextLine(text,startLine)
      @line=startLine
      #line =~ /^(\S+)\s*=\s*(.*)/
      #expression,* = HopExpression.line2expr($2)
      expression = HopExpr.parse(line)
      #ret = LetStatement.new parent, $1, expression
      ret = LetStatement.new parent, expression, startLine
      return ret,startLine+1
    end

    def initialize(parent, expr, line)
      super(parent)
      # @varname=var
      @expression=expr
      @line=line
    end
    
    def hop_clone
      LetStatement.new(@parent,@expression.hop_clone,@line)
    end

    def extract_agg!
      @expression, agg_map = HopExpr.extract_agg @expression
      agg_map
    end

    def hop
      #!!!!!!!!!!!!!!!!TODO!!!!!!!!!!!!!!!!!!
      #!!!!!! scalar/cortege !!!!!!!!!!!!!!!!
      # TODO: support expression lists for tuple assignments
      # right now, it is not implemented

      #value=@expression.evaluate(@parent)
      #VarStor.set(@parent, @varname, value)
      @expression.eval self
    end
  end

  class YieldStatement < Statement
    def initialize(parent,fields=nil)
      @parent=parent
      @id=Hopstance.nextId
      @started=false
      @fields=fields
    end

    def hop_clone
      return YieldStatement.new(@parent,@fields.hop_clone)
    end

    def extract_agg!
      if @reference
        # single expression
        @expression, agg_map = HopExpr.extract_agg @expression
        agg_map
      else
        # parse all fields
        agg_map = {}
        new_fields = {}
        @fields.map do |name, expr|
          unless name[0, 2] == '__'
            new_fields[name], new_agg_map = HopExpr.extract_agg expr
            agg_map = agg_map.merge new_agg_map
          end
        end
        new_fields["__hoplang_cols_order"] = @fields["__hoplang_cols_order"]
        @fields = new_fields
        agg_map
      end
    end  

    def self.createNewRetLineNum(parent,text,pos)
      return YieldStatement.new(parent).createNewRetLineNum(text,pos)
    end

    def createNewRetLineNum(text,pos)
      line,pos=Statement.nextLine(text,pos)
      field_num=1
      # maps names to expressions
      @fields=Hash.new

      raise UnexpectedEOF if line.nil?
      raise (SyntaxError) if(not line.match /^\s*yield(\s*(.*))/)

      # parse expressions
      elist = HopExpr.parse_list $2
#      hop_warn "DDDDDDDDDDDD:: #{elist.size} / #{elist[0].class} / #{elist[0]}"
      if (elist.size == 1) and (elist[0].name == '')
        @reference=true
        @expression = elist[0]
        hop_warn "TRUE! #{@expression.inspect}"
      else
        @reference=false
        names = []
        elist.each do |e|
          name = e.name
          if name == ''
            name = "field_#{field_num}"
          end
          names += [name]
          field_num += 1
          @fields[name] = e
        end
        @fields['__hoplang_cols_order'] = names.join ','
      end

      return self,pos+1
    end

    def hop
      ret = {}
      if @reference
        # one variable
        if @expression.is_stream?(self)
          while ret=@expression.eval(self)
            @parent.do_yield(ret)
          end
          #@parent.do_yield(nil)
          return
        end
        ret = @expression.eval self
      else
        # named list
        @fields.map do |name, expr|
          ret[name] = expr.eval(self) unless name == '__hoplang_cols_order'
        end
        ret['__hoplang_cols_order'] = @fields['__hoplang_cols_order']
      end
      @parent.do_yield(ret)
      #puts "yielded #{ret.inspect}"
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
      hop_warn "debug: #{@expr.inspect}"
      return self, pos + 1
    end # createNewRetLineNum

    def initialize(parent,expr=nil)
      super(parent)
      @expr=expr
    end

    def hop_clone
      return DebugStatement.new(@parent,@expr.hop_clone)
    end
    def hop
      hop_warn "DEBUG(#{@line}): #{@expr.eval(@parent)}"
    end
  end # DebugStatement
end
