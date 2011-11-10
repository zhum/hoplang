require 'citrus'

module Hopsa

  # load HopExpr grammar
  Citrus.load 'hop_expr'

  # base class for hoplang expression
  class HopExpr

    # chains expressions (Citrus matches) with operators (Citrus matches), 
    # returns the resulting hop expression
    # matches must be of the same precedence
    def self.chain(emlist, opmlist)
      elist = emlist.map {|em| em.value}
      oplist = opmlist.map {|opm| opm.value}
      self.chain_helper elist, oplist
    end

    def self.chain_helper(elist, oplist) 
      if oplist.length == 0
        elist[0]
      elsif oplist.length == 1 && oplist[0] == '='
        AssExpr.new elist[0], elist[1]
      elsif oplist[0] == '.'
        elist[1] = DotExpr.new elist[0], elist[1]
        elist.shift
        oplist.shift
        chain_helper elist, oplist
      else
        # arbitrary binary operator on expressions
        elist[1] = BinaryExpr.new elist[0], oplist[0], elist[1]
        elist.shift
        oplist.shift
        chain_helper elist, oplist
      end
    end

    # parses expression, returns HopExpr for top expression
    # in case of error, returns nil and prints error type and location
    def self.parse(line)
      HopExprGram.parse(line, :root => :expr).value
    end

    # parses a list of expressions
    def self.parse_list(line) 
      HopExprGram.parse(line, :root => :topexprlist).value
    end

    # returns the name associated with the expression, default is empty
    def name
      ''
    end

    # eval - evaluate in current execution context

    # ass - assigns a value to the specified reference, available for reference
    def ass(ex, val) 
      warn "#{self.class.inspect}: assignment to this value is not supported"
    end
  end # HopExpr

  # expression containing a single value
  class ValExpr < HopExpr
    attr_reader :val
    def initialize(val)
      @val = val
    end
    def eval(ex)
      return @val
    end
  end # ValExpr

  class RefExpr < HopExpr 
    attr_reader :rname
    # creates a reference expression with a variable
    def initialize(rname) 
      @rname = rname
    end
    def eval(ex)
      VarStor.get(ex, @rname)
    end
    # assigns result to a variable
    def ass(ex, val)
      VarStor.set(ex, @rname, val)
      return nil
    end
  end # RefExpr

  class CallExpr < HopExpr 
    attr_reader :fun_expr, :args
    # function call with function expression (must be RefExpr) and arguments
    def initialize(fun_name, args) 
      @fun_name = fun_name
      @args = args
    end
    def eval(ex) 
      # not implemented
      warn 'warning: function eval not yet implemented'
      return nil
    end
  end # CallExpr

  class DotExpr < HopExpr
    attr_reader :obj, :field_name
    # field reference with object and field name
    def initialize(obj, field_name)
      @obj = obj
      @field_name = field_name
    end
    def eval(ex)
      o = @obj.eval(ex)
      puts "obj = #{o.inspect}"
      r = o[@field_name]
      puts "obj.#{field_name} = #{r}"
      @obj.eval(ex)[@field_name]
    end
    def ass(ex, val)
      @obj.eval(ex)[@field_name] = val
    end
  end # DotExpr

  class UnaryExpr < HopExpr
    attr_reader :op, :expr
    def initialize(op, expr)
      @op = op
      @expr = expr
    end
    def eval(ex) 
      val = @expr.eval(ex)
      case @op
        when '-'
        return -val
        when 'not'
        return !val
        else
        warn "#{@op}: unsupported unary operator"
        return nil
      end
    end
  end # UnaryExpr

  class BinaryExpr < HopExpr
    attr_reader :op, :expr1, :expr2, :short
    def initialize(expr1, op, expr2) 
      @op = op
      @expr1 = expr1
      @expr2 = expr2
      @short = op == 'and' or op == 'or'
    end
    def eval(ex)
      if @short
        #short-circuit
        val1 = @expr1.eval(ex)
        case op 
          when 'and'
          return val1 && @expr2.eval(ex)
          when 'or'
          return val1 || @expr2.eval(ex)
          else
          warn "#{op}: unsupported short-cirtuit binary operator"
          return nil
        end
      else
        #full evaluation
        val1 = @expr1.eval(ex)
        val2 = @expr2.eval(ex)
        case @op
          when '*' 
          return val1 * val2
          when '/' 
          return val1 / val2
          when '%'
          return val1 % val2
          when '+'
          return val1 + val2
          when '-'
          return val1 - val2
          when '<'
          return val1 < val2
          when '>'
          return val1 > val2
          when '<='
          return val1 <= val2
          when '>='
          return val1 >= val2
          when '=='
          return val1 == val2
          when '!='
          return val1 != val2
          when 'xor'
          return val1 ^ val2
          else
          warn "#{@op}: unsupported binary operator"
          return nil
        end # case(op)
      end
    end # eval
  end # BinaryExpr

  # named expression 
  class NamedExpr < HopExpr
    attr_reader :expr
    def initialize(name, expr)
      @name = name
      @expr = expr
    end
    def eval(ex)
      expr.eval(ex)
    end
    # gets the name associated with the expression
    def name
      @name
    end
  end
  
  # assignment expression
  class AssExpr < HopExpr
    attr_reader :expr1, :expr2
    def initialize(expr1, expr2)
      @expr1 = expr1
      @expr2 = expr2
    end
    # performs assignment and always returns nil
    def eval(ex)
      val = expr2.eval(ex)
      expr1.ass(ex, val)
      return nil
    end
  end # AssExpr

  # removed zhumcode begin

  # class HopExpression
  #   OPERATIONS=['+','-','*','/','%']

  #   def initialize(stack)
  #     @expr=stack
  #   end

  #   def self.line2expr(line)
  #     rest=line.strip
  #     stack=Array.new
  #     while rest != '' do;
  #       start,delimiter,rest=rest.partition(/\s+/)
  #       next if start == ''

  #       # operation?
  #       if OPERATIONS.include? start
  #         stack.push HopExprOp.new(start)
  #         next
  #       end

  #       # digit constant?
  #       if start=~/^\d+$/
  #         stack.push start
  #         next
  #       end

  #       # string constant?
  #       if start[0,1]=='"'
  #         if(fin=(start =~ /[^\\]\"/))              #]/
  #           stack.push start[1..fin]
  #         elsif start[1,1]=='"'
  #           stack.push ''
  #         else
  #           raise SyntaxError(l,"No string end found")
  #         end
  #         next
  #       end

  #       # variable?
  #       if start[0,1] =~ /\w/
  #         stack.push HopExprVar.new(start)
  #         next
  #       end

  #       # not processible...
  #       return HopExpression.new(stack),start+delimiter+rest

  #     end # while
  #     return HopExpression.new(stack),''
  #   end # ~line2expr

  #   # evaluate expression in Executor context
  #   def evaluate(ex)
  #     @stack=[]
  #     @expr.each do |el|
  #       case el
  #       when HopExprVar
  #         # evaluate variable
  #         var,dot,field=el.value.partition('.')
  #         if field==''
  #           # scalar
  #           val=VarStor.get(ex,el.value)
  #         else
  #           # cortege field
  #           begin
  #             val=VarStor.get(ex,var)[field]
  #           rescue
  #             warn ">> Opppps: #{var}.#{field}"
  #             nil
  #           end
  #         end
  #         @stack.push val

  #       when Numeric, String
  #         # constant
  #         @stack.push el

  #       when HopExprOp
  #         case el.value
  #         when '+'
  #           a1=@stack.pop
  #           a2=@stack.pop
  #           warn ">>PLUS: #{a1},#{a2}"
  #           raise SyntaxError if a2.nil?
  #           @stack.push a1.to_f+a2.to_f
  #         when '*'
  #           a1=@stack.pop
  #           a2=@stack.pop
  #           raise SyntaxError if a2.nil?
  #           @stack.push a1.to_f*a2.to_f
  #         when '-'
  #           a1=@stack.pop
  #           a2=@stack.pop
  #           warn ">>MINUS: #{a1},#{a2}"
  #           raise SyntaxError if a2.nil?
  #           @stack.push a2.to_f-a1.to_f
  #         when '/'
  #           a1=@stack.pop
  #           a2=@stack.pop
  #           raise SyntaxError if a2.nil?
  #           @stack.push a2.to_f/a1.to_f
  #         when '%'
  #           a1=@stack.pop
  #           a2=@stack.pop
  #           raise SyntaxError if a2.nil?
  #           @stack.push a2.to_f%a1.to_f
  #         else
  #           raise SyntaxError
  #         end
  #       end #~case
  #     end # ~each expression
  #     raise SyntaxError.new(@expr.to_s+' ('+@stack.to_s+')') if @stack.size>1

  #     return @stack.pop
  #   end

  # end

  # class HopExprVar
  #   attr :value

  #   def initialize(str)
  #     @value=str
  #   end

  # end

  # class HopExprOp
  #   attr :value

  #   def initialize(str)
  #     @value=str
  #   end

  # end

  # removed zhumcode end
end
