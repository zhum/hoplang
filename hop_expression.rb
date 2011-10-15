module Hopsa
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
end

