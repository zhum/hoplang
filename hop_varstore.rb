# coding: utf-8
# TODO: deprecate all 'Cortege' things and remove them in future versions
#require 'pp'

class Hash
  # add simple(!) cloninig
  def hop_clone
    ret=self.clone
    self.each do |k,v|
      begin
#        hop_warn "CLONE: #{k} => #{v.inspect}"
        ret[k]=v.hop_clone
      rescue
        begin
          ret[k]=v.clone
        rescue
          ret[k]=v
        end
      end
    end
    ret
  end
end

module Hopsa
  class VarStore

    protected
    attr_reader :scalarStore, :streamStore, :cortegeStore, :ex

    public

    def initialize(ex, dontcopy=nil)
      #hop_warn "New varstore #{object_id}. Parent - #{ex} (#{caller})"
      @ex=ex

      begin
        copy(ex.parent.varStore) if not dontcopy
        return
      rescue NoMethodError

        hop_warn "NEW EMPTY VARSTORE"
        @scalarStore=Hash.new
        @cortegeStore=Hash.new
        @streamStore=Hash.new
      end
    end

    def copy(vs)
      hop_warn "Copy varstore #{@ex.to_s} from #{vs.ex.to_s}."
      @scalarStore=vs.scalarStore.hop_clone
      @cortegeStore=vs.cortegeStore.hop_clone
      @streamStore=vs.streamStore.hop_clone
    end

    def merge(vs)
      hop_warn "Merge varstore #{@ex.to_s} from #{vs.ex.to_s}."
      @scalarStore.merge!(vs.scalarStore.hop_clone)
      @cortegeStore.merge!(vs.cortegeStore.hop_clone)
      @streamStore.merge!(vs.streamStore.hop_clone)
    end

    def addScalar(name)
      @scalarStore[name]=''
    end

    def addStream(name,value=nil)
      @streamStore[name]=value.nil? ? HopPipe.new : value
    end

    def addCortege(name)
      @cortegeStore[name]={}
    end

    def delScalar(name)
      @scalarStore.delete name
    end

    def delStream(name)
      @streamStore.delete name
    end

    def delCortege(name)
      @cortegeStore.delete name
    end

    def getScalar(name)
      #hop_warn ">>Read #{name} = #{@scalarStore[hopid][name]}"

      #!!!! TODO - only in debug version
      raise VarNotFound unless @scalarStore.has_key? name
      @scalarStore[name]
    end

    def getCortege(name)

      #!!!! TODO - only in debug version
      raise VarNotFound unless @cortegeStore.has_key? name
      @cortegeStore[name]
    end

    def getStream(name)

      #!!!! TODO - only in debug version
      raise VarNotFound unless @streamStore.has_key? name
      ret = @streamStore[name].get
#      hop_warn ">>GET #{name} = #{ret}"
      return ret
    end

    def setScalar(name, val)

      #!!!! TODO - only in debug version
      raise VarNotFound unless @scalarStore.has_key? name
      @scalarStore[name]=val
    end

    def setCortege(name, val)

      #!!!! TODO - only in debug version
      raise VarNotFound unless @cortegeStore.has_key? name
      val.each_pair{|key,value|
        #hop_warn ">>SET #{name}: #{hopid} #{name}.#{key} = #{value}"
        @cortegeStore[name][key]=value
      }
    end

    def setStream(name, val)

      #!!!! TODO - only in debug version
#      hop_warn ">>SET #{name} = #{val.inspect}"
      raise VarNotFound unless @streamStore.has_key? name
      @streamStore[name].put val
    end

    def canRead?(name)
        if @streamStore.has_key? name
          return ! @streamStore[name].empty?
        elsif @scalarStore.has_key? name
          return true
        elsif @cortegeStore.has_key? name
          return true
        end

        return false
    end

    def copyStreamFromParent(name,parent)
      @streamStore[name]=parent.streamStore[name]
    end

    def print_store
      ret="VARSTORE [#{@ex.to_s}]\n"
      each do |name,var|
        ret+="::> #{name} = #{var.inspect}\n"
      end
      ret
    end

    def set(name, val)
      if @streamStore.has_key? name
        return @streamStore[name].put val
      elsif @scalarStore.has_key? name
        return @scalarStore[name]=val
      elsif @cortegeStore.has_key? name
        return @cortegeStore[name]=val
      end
      raise VarNotFound, "Var not found(set): #{name} in #{object_id} (#{@ex})\n[#{print_store}]\n"
    end

    def get(name)

      if @scalarStore.has_key? name
        return @scalarStore[name]
      elsif @cortegeStore.has_key? name
        return @cortegeStore[name]
      elsif @streamStore.has_key? name
        return @streamStore[name].get
      end
      raise VarNotFound, "Var not found(get): #{name} (#{@ex})\n[#{print_store}]\n"

    end

    def test_stream(name)
      return @streamStore.has_key? name
    end

    def test_scalar(name)
      return @scalarStore.has_key? name
    end

    def test_cortege(name)
      return @cortegeStore.has_key? name
    end

    def test(name)
      return test_steam(name) || test_scalar(name) || test_scalar(name)
    end

    # variables iterator
    def each_scalar(&block)
      begin
        @scalarStore.each &block
      rescue
      end
    end

    # variables iterator
    def each_cortege(&block)
      begin
        @cortegeStore.each &block
      rescue
      end
    end

    # variables iterator
    def each_stream(&block)
      begin
        @streamStore.each &block
      rescue
      end
    end

    def each(&block)
      each_stream(&block)
      each_cortege(&block)
      each_scalar(&block)
    end

  end
end
