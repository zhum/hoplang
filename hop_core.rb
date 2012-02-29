require 'thread'
require 'json'

module Hopsa
  class HopPipe

    attr_reader :pipe_mutex
#    @pipe_mutex=Mutex.new

    def initialize(copy=nil,old_mutex=nil)
      copy ||= File.pipe
      @read_io, @write_io = copy
      @pipe_mutex= old_mutex.nil? ? Mutex.new : old_mutex
#      hop_warn "MUTEX: #{@pipe_mutex} / #{old_mutex}"
      @data=''
      @buffer=[]
    end

    def hop_clone
      hop_log "PIPE CLONE: #{@pipe_mutex}"
      HopsaPipe.new([@read_io,@write_io],@pipe_mutex)
    end

    def unpack_data(data)
      ret=nil
      begin
        ret=JSON::load data
        unless ret.is_a? Hash
          raise "Not a hash readed: (class=#{ret.class})"
          ret=nil
        end
      rescue => e
        if data =~ /null/
          hop_warn "NULL READED: #{data}"
          return nil
        end
#        return nil if data == ""
        hop_warn "DATA READ ERROR: #{e.message} (#{data.inspect})\n"+e.backtrace.join("\t\n");
        return nil
      end
      return ret
    end

    def get

#      if @read_io.eof?
#        hop_warn "EOF!"
#        return unpack_data @data
#      end

      if @buffer.size >0
        return unpack_data @buffer.shift
      end

      new_data=''
      while true do
        begin
          new_data=@read_io.gets
          @data+=new_data

          ret=nil
          @data.gsub!(/^(.*?)\n~END~RECORD~\n/) {|str|
            str.gsub!(/\n~END~RECORD~\n/,'')
            @buffer << str
            ''
          }
          if @buffer.size>0
            return unpack_data @buffer.shift
          end

        rescue EOFError
#          hop_warn "EOF #{object_id} / #{@data.inspect}"
          begin
            @data+=new_data

            ret=nil
#            hop_warn "GOT DATA1: '#{new_data}'"
            @data.gsub!(/^(.*?)\n~END~RECORD~\n/) {|str|
              str.gsub!(/\n~END~RECORD~\n/,'')
              @buffer << str
              ''
            }
            if @buffer.size>0
              return unpack_data @buffer.shift
            end
          rescue => e
            hop_warn "JSON ERROR: #{@data.inspect}"
          end
          return nil
        rescue Exception => e
          hop_warn "PIPE Error #{object_id} (#{@data}) #{e.message}"+e.backtrace.join("\t\n")
          return nil
        end
      end

      return nil
    end

    def put(value)
      begin
        @write_io.puts(value.to_json)
        @write_io.puts("~END~RECORD~")
      rescue =>e
        hop_warn "WRITE Exception: #{e.message}"
      end
    end

    def empty?
      return true if @buffer.nil?
      return @buffer.empty?
    end

    def to_s
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
      $hoplang_logger.flush
    end
  end

  def hop_warn(str)
    Hopsa::hop_warn(str)
  end

  Thread.abort_on_exception = true

end
