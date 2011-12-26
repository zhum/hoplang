module Hopsa
  class HopPipe

    def initialize
      warn "New Pipe #{self}"
      @read_io, @write_io = File.pipe
    end
    
    def get
    
#      warn "GET #{object_id}"
      if @read_io.eof?
        warn "EOF!"
        return nil
      end

      data=''
      while true do
      begin
        new_data=@read_io.gets
#        warn "GOT #{object_id} -> #{new_data}"
        if new_data.nil? or /~END~RECORD~/ =~ new_data
          ret=YAML::load data
          warn "GET #{object_id} VAL: #{ret.inspect}"
          warn "AND EOF!" if new_data.nil?
          warn "NIL!!! #{ret.class}" if ret.class != Hash
          return ret
        else
          data+=new_data
        end
      rescue EOFError
        warn "EOF"
        return YAML::load data
      rescue => e
        warn "EEEEEEEE (#{data}) #{e}"
        return YAML::load data
      end
      end
            
      while true do
        begin
          Thread.critical=true
#          warn "PIPE: #{@buffer.size}"
          if @buffer.nil?
            warn "EMTY PIPE"
            Thread.critical=false
            Thread.pass
          else
            ret = @buffer.shift
            Thread.critical=false
            return ret
          end
        rescue => e
          Thread.critical=false
          warn "PIPE IS EMPTY. Wait for new values... #{e}"
          Thread.pass
#          sleep 1
        end
      end
    end

    def put(value)
    
#      warn "PUT #{object_id} #{value.inspect}"
      @write_io.puts(value.to_yaml)
      @write_io.puts('~END~RECORD~')
      @write_io.sync
    end

    def empty?
    
      return @read_io.eof?
      
      return True if @buffer.nil?
      return @buffer.empty?
    end

    def to_s
#      "#HopPipe: #{@buffer.size} elements inside."
      @read_io.nil? ? "HopPipe: non-init" : "HopPipe: is #{object_id}"
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

