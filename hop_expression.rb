# coding: utf-8
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

    # number of aggregation variables created
    @@agg_var_count = 0

    # get the name of a new aggregation variable
    # must not be called from multiple threads simultaneously
    def self.new_agg_var
      name = "__agg_var_" + @@agg_var_count.to_s
      @@agg_var_count += 1
      name
    end

    # extract aggregation variables; this is the version for the client code
    # expr - the expression from which to extract aggregation variables
    # returns - (new_expr, agg_var_map):
    # new_expr - the transformed expression which must be used instead
    # agg_var_map - {agg_var => (init_val, update_expr)}
    # based on aggregation variable map, a hopstance can add statements
    def self.extract_agg(expr)
      agg_var_map = {}
      new_expr = extract_agg_into expr, agg_var_map
      [new_expr, agg_var_map]
    end

    # extracts aggregation variables and accumulates them into the map; this is
    # the version called internally; the new expression is returned
    def self.extract_agg_into(expr, map)
      if expr.kind_of?(Array)
        # list of expressions
        res_exprs = expr.map do |e|
          extract_agg_into e, map
        end
        return res_exprs
      elsif expr.kind_of?(CallExpr) && expr.fun.aggregate?
        agg_var = new_agg_var
        neutral = expr.fun.neutral
        expr2 = extract_agg_into expr.args[0], map
        agg_ref = RefExpr.new agg_var
        agg_direct = expr.fun.direct
        update_expr = nil
        if expr.fun.op?
          update_expr = BinaryExpr.new agg_ref, agg_direct, expr2
        else
          update_expr = CallExpr.new agg_direct, [agg_ref, expr2]
        end
        agg_expr = AssExpr.new agg_ref, update_expr
        map[agg_var] = [neutral, agg_expr]
        return agg_ref
      else
        # new_members = expr.expr_members.map do |e|
        #   extract_agg_into e, map
        # end
        # expr.expr_subst new_members
        return expr.expr_subst extract_agg_into expr.expr_members, map
      end
    end

    # returns the array of subexpression of a given expression; an empty array
    # is returned for leaves. Attributes of expressions that are not members,
    # such as names, field names etc., are not returned
    def expr_members
      []
    end

    # clones the expression with same type and non-members, but with new members supplied
    def expr_subst(new_members)
      self
    end

    # destructive version of expr_subst
    def expr_subst!(new_members)
      self
    end

    def is_stream?(ex)
      false
    end

    def initialize(*args)
      @code_line=Statement.current_line || 0
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

    def db_conv(ex,db)
      hop_warn "DB_CONV: #{db.inspect} / #{self.class}"
      ret_db,ret_hop = self.to_db(ex,db)
      hop_warn "DB_CONV2: #{ret_db.inspect} / #{ret_hop}"
      return db.wrapper(ret_db),ret_hop unless ret_db.nil?
      return nil,ret_hop
    end

  end # HopExpr

  # expression containing a single value
  class ValExpr < HopExpr
    attr_reader :val

    def initialize(val)
      super
      @val = val
    end

    def eval(ex)
      return @val
    end

    def to_db(ex,db)
      #val=@expr.eval(ex)
      #hop_warn "VAL=#{@val}"
      if @val =~ /^\d+$/
        val=@val
      else
        val="'"+@val.to_s+"'"
      end
      return db.value(val),ex #???
    end

    def to_s
      @val
    end
  end # ValExpr

  class RefExpr < HopExpr
    attr_reader :rname
    # creates a reference expression with a variable
    def initialize(rname)
      super
      @rname = rname
    end

    def eval(ex)
#      hop_warn "REF #{@rname} =>#{ex.to_s}\n#{ex.varStore.print_store}"
      begin
        res = ex.varStore.get @rname
        res
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
    end

    def is_stream?(ex)
      return ex.varStore.test_stream @rname
    end

    # assigns result to a variable
    def ass(ex, val)
      begin
        ex.varStore.set @rname, val
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
      return nil
    end

    def to_db(ex,db)
      hop_warn "REF=#{@rname}"
      if @rname == db.db_var
        # special case of iterator variable
        db.value @rname, self
      else
        # just an outer variable, get the value
        begin
          ex.varStore.get @rname, self
        rescue => e
          raise #e.message.chomp+' at line '+@code_line.to_s
        end
      end
    end

    def to_s
      @rname
    end
  end # RefExpr

  class CallExpr < HopExpr
    attr_reader :fun_name, :args, :fun
    # function call with function expression (must be RefExpr) and arguments
    def initialize(fun_name, args)
      @fun_name = fun_name
      @args = args
      @fun = Function.by_name_argnum fun_name, args.count
    end
    def eval(ex)
      evaluated_args = args.map do |arg| arg.eval ex end
      res = fun.call evaluated_args
      res = res.to_s if fun.post_conv
      res
    end
    def expr_members
      args
    end
    def expr_subst(new_members)
      CallExpr.new @fun_name, new_members
    end
    def expr_subst!(new_members)
      @args = new_members
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
      super
      @obj = obj
      @field_name = field_name
    end
    def eval(ex)
      begin
        o = @obj.eval(ex)
        unless o.is_a? Hash
          hop_warn "applying . to not a tuple (#{o.class} = #{o.inspect}) at #{@code_line}#{ex.varStore.print_store}"
          return nil
        end
        r = o[@field_name]
        hop_warn "no field #{@field_name} in object (#{o.inspect})" if !r
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
      r
    end
    def expr_members
      [@obj]
    end
    def expr_subst(new_members)
      DotExpr.new new_members[0], @field_name
    end
    def expr_subst!(new_members)
      @obj = new_members[0]
    end
    def ass(ex, val)
      begin
        @obj.eval(ex)[@field_name] = val
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
    end

    def to_db(ex,db)
      #val=@obj.eval(ex)
      begin
        return db.value(@field_name), self
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
      #val[@field_name]
    end

    def to_s
      "#{obj}.#{field_name}"
    end
  end # DotExpr

  class UnaryExpr < HopExpr
    attr_reader :op, :expr
    def initialize(op, expr)
      super
      @op = op
      @expr = expr
    end
    def eval(ex)
      begin
        val = @expr.eval(ex)
        case @op
          when '-'
            return (-val.to_f).to_s
          when 'not'
            return !val
          when 'int'
            hop_warn "#{@op}: this operation is deprecated, use function instead"
            return val.to_i
          else
            hop_warn "#{@op}: unsupported unary operator"
            return nil
        end
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
    end
    def expr_members
      [@expr]
    end
    def expr_subst(new_members)
      UnaryExpr.new @op, new_members[0]
    end
    def expr_subst!(new_members)
      @expr = new_members[0]
    end
    def to_db(ex,db)
      #val=@expr.eval(ex)
      begin
        return db.unary(val,@op), self
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
    end

    def to_s
      @op.to_s+@expr.to_s
    end
  end # UnaryExpr

  # named expression
  class NamedExpr < HopExpr
    attr_reader :expr
    def initialize(name, expr)
      super
      @name = name
      @expr = expr
    end
    def eval(ex)
      begin
        expr.eval(ex)
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
    end
    def expr_members
      [@expr]
    end
    def expr_subst(new_members)
      NamedExpr.new @name, new_members[0]
    end
    def expr_subst!(new_members)
      @expr = new_members[0]
    end
    # gets the name associated with the expression
    def name
      @name
    end

    def to_db(ex,db)
      #val=eval(ex)
      begin
        return db.value(@name), self
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
    end

  end

  # assignment expression
  class AssExpr < HopExpr
    attr_reader :expr1, :expr2
    def initialize(expr1, expr2)
      super
      @expr1 = expr1
      @expr2 = expr2
    end
    # performs assignment and always returns nil
    def eval(ex)
#      hop_warn "DO #{expr2}"
      val = expr2.eval(ex)
      begin
        expr1.ass(ex, val)
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
      return nil
    end
    def expr_members
      [@expr1, @expr2]
    end
    def expr_subst(new_members)
      AssExpr.new new_members[0], new_members[1]
    end
    def expr_subst!(new_members)
      @expr1 = new_members[0]
      @expr2 = new_members[1]
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
      super
      @op = op
      @expr1 = expr1
      @expr2 = expr2
      @short = SHORT_OPS.include? op
      @pre_conv = PRECONV_OPS.include? op
      @post_conv = POSTCONV_OPS.include? op
    end

    def eval(ex)
      begin
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
      rescue => e
        raise #e.message.chomp+' at line '+@code_line.to_s
      end
    end # eval
    def expr_members
      [@expr1, @expr2]
    end
    def expr_subst(new_members)
      BinaryExpr.new new_members[0], @op, new_members[1]
    end
    def expr_subst!(new_members)
      @expr1 = new_members[0]
      @expr2 = new_members[1]
    end
    # return: DB_EXPRESSION, hoplang string
    def to_db(ex,db)
      begin
      db_val1, hop_val1 = @expr1.to_db(ex,db)
      db_val2, hop_val2 = @expr2.to_db(ex,db)
      if @short
        #short-circuit
        if not db_val1.nil? and not db_val2.nil?
          #all calculated

          case op
            when 'and'
              return db.and(db_val1, db_val2), self
            when 'or'
              return db.or(db_val1, db_val2), self
            else
              hop_warn "#{op}: unsupported short-cirtuit binary operator"
              return nil, self
          end
        else
          # sometnig cannot be calculated
          case op
            when 'or'
              # 8( all DB must be searched...
              return nil, self
            when 'and'
              return db_val2, self if(db_val1.nil?)
              return db_val1, self
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

        return db_res, self
      end
      rescue => e
        raise #e.message+' at line '+@code_line.to_s
      end
    end # to_db

    def to_s
      '('+@expr1.to_s+@op.to_s+@expr2.to_s+')'
    end
  end # BinaryExpr

end
