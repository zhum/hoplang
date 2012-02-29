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
      HopExprGram.parse(line.to_s, :root => :expr).value
    end

    # parses a conditional expression, such as allowed in while, if and where
    def self.parse_cond(line)
      HopExprGram.parse(line.to_s, :root => :condexpr).value
    end

    # parses a list of expressions
    def self.parse_list(line)
      HopExprGram.parse(line, :root => :topexprlist).value
    end

    # returns the name associated with the expression, default is empty
    def name
      ''
    end

    def executor=(ex)
    end

    def hop_clone
      self
    end

    # eval - evaluate in current execution context

    # ass - assigns a value to the specified reference, available for reference
    def ass(ex, val)
      hop_warn "#{self.class.inspect}: assignment to this value is not supported"
    end

    def to_s
      ''
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

    def to_db(ex,db)
      #val=@expr.eval(ex)
      hop_warn "VAL=#{@val}"
      return db.value(@val),ex #???
    end

    def to_s
      @val
    end
  end # ValExpr

  class RefExpr < HopExpr
    attr_reader :rname
    # creates a reference expression with a variable
    def initialize(rname)
      @rname = rname
    end
    def eval(ex)
#      hop_warn "REF #{@rname} =>#{ex.to_s}\n#{ex.varStore.print_store}"
      ex.varStore.get @rname
    end
    # assigns result to a variable
    def ass(ex, val)
      ex.varStore.set @rname, val
      return nil
    end

    def to_db(ex,db)      
      hop_warn "REF=#{@rname}"
      if @rname == db.db_var
        # special case of iterator variable
        db.value @rname
      else
        # just an outer variable, get the value
        ex.varStore.get @rname
      end
    end

    def to_s
      @rname
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
      hop_warn 'warning: function eval not yet implemented'
      return nil
    end

    def to_db(ex,db)
      hop_warn 'warning: function eval not yet implemented'
      #db.function()
      return nil,nil
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
      unless o.is_a? Hash
        hop_warn "applying . to not a tuple (#{o.class} = #{o.inspect}) #{ex.varStore.print_store}"
        return nil
      end
      # puts "obj = #{o.inspect}"
      r = o[@field_name]
      # puts "obj.#{field_name} = #{r}"
      hop_warn "no field #{@field_name} in object (#{o.inspect})" if !r
      r
    end
    def ass(ex, val)
      @obj.eval(ex)[@field_name] = val
    end

    def to_db(ex,db)
      #val=@obj.eval(ex)
      return db.value(@field_name), ex
      #val[@field_name]
    end

    def to_s
      "#{obj}.#{field_name}"
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
          return (-val.to_f).to_s
        when 'not'
          return !val
        when 'int'
          return val.to_i
        else
          hop_warn "#{@op}: unsupported unary operator"
          return nil
      end
    end

    def to_db(ex,db)
      #val=@expr.eval(ex)
      return db.unary(val,@op), ex
    end

    def to_s
      @op.to_s+@expr.to_s
    end
  end # UnaryExpr

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

    def to_db(ex,db)
      #val=eval(ex)
      return db.value(@name), ex
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
#      hop_warn "DO #{expr2}"
      val = expr2.eval(ex)
      expr1.ass(ex, val)
      return nil
    end

    def to_db(ex,db)
      hop_warn "Assingment not supported in where-expression"
      return nil,nil
    end
  end # AssExpr

  class BinaryExpr < HopExpr
    # operators which are short-circuit
    SHORT_OPS = ['and', 'or']
    # pre-conversion operators
    PRECONV_OPS = ['*', '/', '+', '-', '<=', '>=', '<', '>']
    # post-conversion operators
    POSTCONV_OPS = ['*', '/', '+', '-']
    # relational operators
    attr_reader :op, :expr1, :expr2, :short

    def initialize(expr1, op, expr2)
      @op = op
      @expr1 = expr1
      @expr2 = expr2
      @short = SHORT_OPS.include? op
      @pre_conv = PRECONV_OPS.include? op
      @post_conv = POSTCONV_OPS.include? op
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
            hop_warn "#{op}: unsupported short-cirtuit binary operator"
            return nil
        end
      else
        #full evaluation
        val1 = @expr1.eval(ex)
        val2 = @expr2.eval(ex)
        if @pre_conv
          val1 = val1.to_f
          val2 = val2.to_f
        end
        res = nil
        case @op
          when '*'
          res = val1 * val2
          when '/'
          res = val1 / val2
          when '+'
          res = val1 + val2
          when '-'
          res = val1 - val2
          when '&'
          # string concatenation
          res = val1 + val2
          when '<'
          res = val1 < val2
          when '>'
          res = val1 > val2
          when '<='
          res = val1 <= val2
          when '>='
          res = val1 >= val2
          when '<.'
          res = val1 < val2
          when '>.'
          res = val1 > val2
          when '<=.'
          res = val1 <= val2
          when '>=.'
          res = val1 >= val2
          when '=='
          res = val1 == val2
          when '!='
          res = val1 != val2
          when 'xor'
          res = val1 ^ val2
          else
          hop_warn "#{@op}: unsupported binary operator"
          return nil
        end # case(op)
        res = res.to_s if @post_conv
        return res
      end
    end # eval

    # return: DB_EXPRESSION, hoplang string
    def to_db(ex,db)
      db_val1, hop_val1 = @expr1.to_db(ex,db)
      db_val2, hop_val2 = @expr2.to_db(ex,db)
      if @short
        #short-circuit
        if not db_val1.nil? and not db_val2.nil?
          #all calculated

          case op
            when 'and'
              return db.and(db_val1, db_val2), ex
            when 'or'
              return db.or(db_val1, db_val2), ex
            else
              hop_warn "#{op}: unsupported short-cirtuit binary operator"
              return nil, nil
          end
        else
          # sometnig cannot be calculated
          case op
            when 'or'
              # 8( all DB must be searched...
              return nil, ex
            when 'and'
              return db_val2, ex if(db_val1.nil?)
              return db_val1, ex
            else
              hop_warn "#{op}: unsupported short-cirtuit binary operator"
              return nil, nil
          end
        end #if calculated
      else
        #full evaluation
        #if @pre_conv
        #  hop_val1 = hop_val1.to_f
        #  hop_val2 = hop_val2.to_f
        #end
        res = nil
        db_res = db.binary(db_val1,db_val2,@op)

        #res = res.to_s if @post_conv

        return db_res, res
      end
    end # to_db

    def to_s
      '('+@expr1.to_s+@op.to_s+@expr2.to_s+')'
    end
  end # BinaryExpr

end
