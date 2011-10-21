class EvaluatorError <StandardError
end

class EvaluatorData
#  attr_accessor :line_values
  attr_accessor :values
  attr_accessor :value

  def [](f)
    return @values[f]
  end

#  def initialize
#    p "ED"
#  end
end

class Evaluator
  attr_reader :data

  # do initialization
  def self.create(expr)

    if expr.class == Array
      stack = expr
    else
      stack = expr.split
    end

    name=stack.shift

#    p ":: #{name} / #{stack}."
    case name
    when /^s'(\S+)'$/
      ret=CondStreamEvaluator.new(name,stack)
    when 'select'
      ret=SelectEvaluator.new(name,stack)
    when /^min|max|sum$/
      ret=AgregateFuncEvaluator.new(name,st‭ack)
    when /^eq|ne|gt|lt$/
      ret=ConditionEvaluator.new(name,stack)
    when /\+|\-|\*|\//
      ret=BiOperationEvaluator.new(name,stack)
    when /^'(\S+)'$/‬
      ret=StringConstEvaluator.new($1,stack)
    else
      ret=FieldReadEvaluator.new(name,stack)
    end
#    p "CREATED: #{ret.class.to_s} (#{name})"
    return ret
  end

  def accepts_action?(act)
    return false
  end

  def add_action(act)
  end
end

class StreamEvaluator < Evaluator
  # do initialization
  def initialize(name,expr)
    @cur=EvaluatorData.new

    if name =~ /^s'(\S+)'$/
      @name=$1
      @file=open($1,"r")
      read_fieldnames
    else
      raise EvaluatorError "Bad stream name: #{name}"
    end
  end

  def get_next(cur)
#    p "GET_NEXT: #{self.class.to_s}"

    @cur.values=Hash.new
    @line_values=@file.readline.chomp.split(/\s*,\s*/)
#    p "Stream Read: #{@line_values}"
    raise IOError if @line_values.size<@value_names.size

    0.upto(@line_values.size-1) { |i|
#      p "FIELD #{i}: #{@value_names[i]} = #{@line_values[i]}"
      @cur.values[@value_names[i]]=@line_values[i]
    }
#    p "read: #{@cur.line_values}"
    return @cur
  end

  def read_fieldnames
    @value_names=@file.readline.chomp.split(/\s*,\s*/)
  end
end

class CondStreamEvaluator < StreamEvaluator
  def accepts_action?(act)
    #return false
    return ['gt','lt','eq','ne'].include?(act)
  end

  def get_next(cur)
    @cur.values=Hash.new
    while true
      @line_values=@file.readline.chomp.split(/\s*,\s*/)
      p "CondStream Read: #{@line_values}"
      raise IOError if @line_values.size<@value_names.size

      0.upto(@line_values.size-1) { |i|
#        p "FIELD #{i}: #{@value_names[i]} = #{@line_values[i]}"
        @cur.values[@value_names[i]]=@line_values[i]
      }

      # check condition
      break if @condition.nil?
      cond=@condition.get_next(@cur)
      p "VAL: #{cond.value}"
      break if cond.value
    end

#    p "read: #{@cur.line_values}"
    return @cur
  end

  def add_action(act)
    #act = ConditionEvaluator
    @condition = act
  end
end

class SelectEvaluator < Evaluator
  def initialize(name,stack)

    @select_stream=Evaluator.create(stack)

    if @select_stream.accepts_action?(stack[0])
      @select_stream.add_action(Evaluator.create(stack))
    end

    @select_args = Array.new
    while stack[0] != ';'
      e=Evaluator.create(stack)
      @select_args.push e
    end
  end

  def get_next(cur)
    begin #loop !!!!!!!!!!!!!!!!!!!!!!!!!!
      #TODO:  make full condition
      p "GET_NEXT: #{self.class.to_s}"

      selection_condition=true
      result=@select_stream.get_next(cur)
#      p "RAW STREAM: #{result.values}"
      @select_args.each { |sel|
        cond=sel.get_next(result).value
#        p "SELECT RAW COND: #{cond}"
        selection_condition = selection_condition & cond
        p "SELECT COND: #{selection_condition}"
      }
    end until selection_condition
    selection_condition ? result : nil
  end
end

class AgregateFuncEvaluator < Evaluator
  def initialize(name,stack)
      # args: function, selection(from stream)
      @name=name
      #TODO: new Stream

      @compute=Evaluator.create(stack)
      @stream=Evaluator.create(stack)
      #TODO: new selection

      @result=EvaluatorData.new
      @result.value=nil
  end

  def get_next(cur=EvaluatorData.new)
    next_value=EvaluatorData.new
    p "GET_NEXT: #{self.class.to_s}"
    begin
      while true
        next_value=@stream.get_next(cur)
        break if next_value.nil?

#        p "!FUNC_STREAM=#{next_value.line_values}"
        comp_result=@compute.get_next(next_value)
        p "!FUNC_VAL: #{comp_result.value}"
#        redo unless comp_result

#        @cur=func_result
        @result.value=func_evaluate(@result.value,comp_result.value)
      end
    rescue => e
      p "ERR: #{e.message} / #{e.backtrace}"
    end
    p "FUNC_RESULT: #{@result.value}"
    @result
  end

  # digits!!!!!!!
  def func_evaluate(result,next_value)
    if result.nil?
      return next_value
    end
    case @name
    when 'min'
      result=[next_value,result].min
    when 'max'
      p "MAX: #{next_value} #{result}"
      result=[next_value,result].max
    when 'sum'
      result+=next_value
    end
    return result
  end

end

class ConditionEvaluator < Evaluator
  def initialize(name,stack)
    @name=name
    @arg1=Evaluator.create(stack)
    @arg2=Evaluator.create(stack)
  end

  def get_next(cur=EvaluatorData.new)
    p "GET_NEXT: #{self.class.to_s}"
    a1=@arg1.get_next(cur).value
    a2=@arg2.get_next(cur).value
    cur.value=op_evaluate(a1,a2)
    p "COMPARE: #{@name} #{a1} #{a2} #{cur.value}"
    return cur
  end

  def op_evaluate(a1,a2)
    case @name
    when 'eq'
      a1==a2
    when 'ne'
      a1!=a2
    when 'gt'
      a1.to_f>a2.to_f
    when 'lt'
      a1.to_f<a2.to_f
    else
      raise EvaluatorError("Bad comparation #{@name}")
    end
  end
end


class BiOperationEvaluator < Evaluator
  def initialize(name,stack)
    @name=name
    @arg1=Evaluator.create(stack)
    @arg2=Evaluator.create(stack)
  end

  def get_next(cur=EvaluatorData.new)
#    p "GET_NEXT: #{self.class.to_s}"
    a1=@arg1.get_next(cur).value
    a2=@arg2.get_next(cur).value
    cur.value=op_evaluate(a1,a2)
    cur
  end

  def op_evaluate(a1,a2)
    case @name
    when '+'
      a1.to_f+a2.to_f
    when '-'
      a1.to_f-a2.to_f
    when '*'
      a1.to_f*a2.to_f
    when '/'
      a1.to_f/a2.to_f
    else
      raise EvaluatorError("Bad operation #{@name}")
    end
  end
end

class StringConstEvaluator < Evaluator
  def initialize(name,stack)
    @name=name
  end

  def get_next(cur)
#    p "GET_NEXT: #{self.class.to_s}"
    ret=EvaluatorData.new
    ret.value=@name
    return ret
  end
end

class FieldReadEvaluator < Evaluator
  attr_accessor :value
  def initialize(name,stack)
    @name=name
  end

  def get_next(cur)
#    p "GET_NEXT: #{self.class.to_s}"
    @cur=cur
    @cur.value=cur[@name]
#    p "Field: #{@name} = #{@cur.value}"
    return @cur
  end
end

e=Evaluator.create("sum + '1' * - end start np select s'test_stream.csv' gt np '10' ;");
result=e.get_next()
p "Result: #{result.value}"

