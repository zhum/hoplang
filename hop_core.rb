require 'thread'

module Hopsa
  class HopPipe

    def initialize(copy=nil)
      copy ||= File.pipe
      @read_io, @write_io = copy
    end

    def hop_clone
      HopsaPipe.new(@read_io)
    end

    def get

      if @read_io.eof?
        hop_warn "EOF!"
        return nil
      end

      data=''
      while true do
      begin
        new_data=@read_io.gets
        if new_data.nil? or /~END~RECORD~/ =~ new_data
          ret=YAML::load data
#          hop_warn "PIPE GET #{object_id} VAL: #{ret.inspect}"
          hop_warn "AND EOF!" if new_data.nil?
          hop_warn "PIPE NIL!!! (class=#{ret.class})" if ret.class != Hash
          return ret
        else
          data+=new_data
        end
      rescue EOFError
        hop_warn "EOF #{object_id}"
        return YAML::load data
      rescue => e
        hop_warn "PIPE Error #{object_id} (#{data}) #{e}"
        return YAML::load data
      end
      end

      while true do
        begin
          Thread.critical=true
#          hop_warn "PIPE: #{@buffer.size}"
          if @buffer.nil?
            hop_warn "EMTY PIPE"
            Thread.critical=false
            Thread.pass
          else
            ret = @buffer.shift
            Thread.critical=false
            return ret
          end
        rescue => e
          Thread.critical=false
          hop_warn "PIPE IS EMPTY. Wait for new values... #{e}"
          Thread.pass
#          sleep 1
        end
      end
    end

    def put(value)

#      hop_warn "PUT #{object_id} #{value.inspect}"
      @write_io.puts(value.to_yaml)
      @write_io.puts('~END~RECORD~')
      @write_io.sync
    end

    def empty?

      return @read_io.eof?

      return true if @buffer.nil?
      return @buffer.empty?
    end

    def to_s
#      "#HopPipe: #{@buffer.size} elements inside."
      @read_io.nil? ? "HopPipe: non-init" : "HopPipe: is #{object_id}"
    end
    private
      attr_reader :read_io, :write_io
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

    def hop_clone
      ret=HopChain.new(@executor)
      @chain.each {|el|
        ret.add el.hop_clone
      }
      ret
    end

    def executor=(executor)
      @executor=executor
      @chain.each do |el|
        el.executor=executor
      end
    end

    attr_reader :executor
    attr_reader :chain

  end

  def self.hop_warn(str)
    $hoplang_warn_mutex ||= Mutex.new

    if $hoplang_logger.nil?
      begin
        $hoplang_logger=File.open('hoplog.log','a')
      rescue
        $hoplang_logger=File.open('/dev/null','a')
      end
    end

    $hoplang_warn_mutex.synchronize do
      $hoplang_logger.print str,"\n"
    end
  end

  def hop_warn(str)
    Hopsa::hop_warn(str)
  end

  Thread.abort_on_exception = true

end

