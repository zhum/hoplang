# Hoplang function calls are defined here

require 'rubygems'
require 'date'

module Hopsa

  # implementation of specific hopsa functions - for functions whose
  # implementation takes more than 1 line
  class HopsaFuns
    # converts a string into a date which is the number of microseconds since
    # epoch for the specific local date (Time.local is used in ruby code)
    def self.date(str)
      case str.strip
      when /(?<y>(?:\d\d)?\d\d)[-\.\/](?<m>\d?\d)[-\.\/](?<d>\d?\d)\s+
            (?:(?<ho>\d\d):(?<mi>\d\d))?/x
        t = nil
        y = $~[:y].to_i
        y += 2000 if y < 100
        if $~[:ho]
          t = Time.local y, $~[:m], $~[:d], $~[:ho], $~[:mi]
        else
          t = Time.local y, $~[:m], $~[:d]
        end
        t.tv_sec * 1000000 + t.tv_usec
      else
        # try parse as cdate
        begin
          t = (DateTime.parse str).to_time
          # HACK, can cause problems if dates are far from now
          ts = (t.tv_sec - Time.now.utc_offset) * 1000000 + t.tv_usec
          ts
        rescue
          hop_warn "#{str}: not a valid date; format is [yy]yy-mm-dd HH:MM" + 
            " .-/ separators, or cdate are allowed in date part"
          throw
        end
      end
    end
  end
#  class HopsaFuns
#    def self.int x
#      x.to_i
#    end
#    def self.min x, y
#      [x, y].min
#    end
#    def self.max x, y
#      [x, y].max
#    end
#    # to be called from "count" only, not for direct use
#    def self._incr x, y
#      x.to_f + 1
#    end
#  end

  # a Hoplagn function; either a directly called function, or an aggregate function
  class Function

    attr_reader :name

    # map of all functions
    @@fun_map = {}

    def self.key_for_map(name, argnum)
      "#{name}'#{argnum}"
    end

    # gets a function by name
    def self.by_name_argnum(name, argnum)
      key = key_for_map name, argnum
      f = @@fun_map[key]
      warn "function #{name} with #{argnum} parameter(s) is not defined" unless f
      f
    end

    # adds a new aggregate
    def self.agg(name, direct, neutral)
      key = key_for_map name, 1
      warn "function #{name} is redefined" if @@fun_map[key]
      @@fun_map[key] = AggregateFunction.new name, direct, neutral
    end

    # adds a new direct function
    def self.direct(name, argnum, pre_conv, post_conv, code)
      key = key_for_map name, argnum
      warn "function #{name} with #{argnum} parameter(s) is redefined"  if @@fun_map[key]
      @@fun_map[key] = DirectFunction.new(name, argnum, pre_conv, post_conv, code)
    end

    # initializes the list of functions
    def self.load
      # direct functions
      direct "int", 1, false, true, lambda{|x| x.to_i}
      direct "min", 2, true, true, lambda{|x,y| [x,y].min}
      direct "max", 2, true, true, lambda{|x,y| [x,y].max}
      direct "incr", 2, false, true, lambda{|x,y| x.to_f+1 }
      direct "date", 1, false, true, lambda{|s| HopsaFuns.date s}
      # aggregate functions
      agg "min", "min", "1e300"
      agg "max", "max", "-1e300"
      agg "sum", "+", "0"
      agg "prod", "*", "1"
      agg "count", "incr", "0"
    end

    # creates a new function
    def initialize(name, arg_num)
      @name = name
      @arg_num = arg_num
    end

    # called when a function is called from Hoplang; overridden in derived classes
    def call(args)
      raise Exception
    end

    # whether the function is aggregate
    def aggregate?
      false
    end
  end # class Function

  # directly called function
  class DirectFunction < Function

    attr_reader :post_conv, :ruby_fun

    # post_conv - whether result must be converted to string
    # ruby_fun - the name of (non-instance) ruby fun to be called
    def initialize(name, argnum, pre_conv, post_conv, code)
      super name, argnum
      @pre_conv = pre_conv
      @post_conv = post_conv
      @code = code
    end

    def call(args)
      if @pre_conv
        args.map! {|arg| arg.to_f}
      end
      #puts "args = " + args.inspect
      #res = eval("#{ruby_fun} " + (args.map{|arg| arg.inspect}.join ','))
      res = @code.call(*args)
      res = res.to_s if @post_conv
    end
  end # DirectFunction

  # aggregate function, must be preprocessed in a special way. When called
  # directly, returns the argument with which it was called
  class AggregateFunction < Function

    attr_reader :direct, :neutral

    # direct - name of direct function or operation to be called
    # neutral - neutral element
    # number of arguments is always 1
    def initialize(name, direct, neutral)
      super name, 1
      @direct = direct
      @neutral = neutral
    end

    def call(args)
      warn "aggregation function #{@name} may not be called directly"
      args[0]
    end

    def aggregate?
      true
    end

    # whether the direct function name is an operator
    def op?
      !(id_start? direct[0,1])
    end

    # whether the character is a possible id start char
    def id_start?(c)
      c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_'
    end

  end # AggregateFunction

end
