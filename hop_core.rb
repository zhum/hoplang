# coding: utf-8
require 'thread'
require 'json'

module Hopsa
  class HopPipe

#    attr_reader :pipe_mutex

    def initialize(copy=nil)
      copy ||= File.pipe
      @read_io, @write_io = copy
#      @pipe_mutex= old_mutex.nil? ? Mutex.new : old_mutex
      @data=''
      @buffer=[]
    end

    def hop_clone
#      hop_log "PIPE CLONE: #{@pipe_mutex}"
      HopsaPipe.new([@read_io,@write_io])
    end

    def unpack_data(data)
      if data=='NIL'
        hop_warn "TRUE NIL READED!"
        return nil
      end

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
        return nil if data == ''
        hop_warn "DATA READ ERROR: #{e.message} (#{data.inspect})\n"+e.backtrace.join("\t\n");
        return nil
      end
      return ret
    end

    def get
      new_data=@read_io.gets("\n")
      return unpack_data(new_data.chomp!)
    end

    def put(value)
      begin
        if(value.nil?)
          @write_io.puts("NIL\n")
        else
          @write_io.puts(value.to_json+"\n")
        end
        #hop_warn "PUT: #{value.inspect}"
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

  class BadDriver <StandardError
  end

  class HopsaDBDriver
    def initialize(parent,source,current_var,where)
      @parent,@source,@current_var,@where=parent,source,current_var,where
      if where.nil? or where == ''
        @where_expression=nil
      else
        @where_expression=HopExpr.parse(where)
      end
    end

    def readSource
      raise BadDriver("Diver not implemented corretly!")
    end
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

end
