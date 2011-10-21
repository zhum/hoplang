module Hopsa
  class HopPipe
    def get
      begin
#        warn "PIPE: #{@buffer[0]}"
        return @buffer.shift
      rescue
#        warn "PIPE IS NIL"
        return nil
      end
    end

    def put(value)
      @buffer ||= Array.new
#      warn "PIPE put: #{value}"
      if(value.class == Hash)
        @buffer.push(value.to_csv)
      else
        @buffer.push(value)
      end
    end

    def empty?
      return nil if @buffer.nil?
      return @buffer.empty?
    end

    def to_s
      "#HopPipe: #{@buffer.size} elements inside."
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
      @chain.each {|el| el.hop}
    end

    def to_s
      "#HopChain (#{@chain.size} statements)"
    end
  end
end

