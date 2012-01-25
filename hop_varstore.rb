# TODO: deprecate all 'Cortege' things and remove them in future versions

class Hash
  # add simple(!) cloninig
  def hop_clone
    ret=self.clone
    self.each do |k,v|
      ret[k]=v.clone
    end
    ret
  end
end

module Hopsa
  class VarStore

    protected
    attr_reader :scalarStore, :streamStore, :cortegeStore

    public

    def initialize(ex, dontcopy=nil)
      warn "New varstore #{object_id}. Parent - #{ex} (#{caller})"
      @ex=ex

      begin
        copy(ex.parent.varStore) if not dontcopy
        return
      rescue NoMethodError

        warn "NEW EMPTY VARSTORE"
        @scalarStore=Hash.new
        @cortegeStore=Hash.new
        @streamStore=Hash.new
      end
    end

    def copy(vs)
      warn "Copy varstore #{object_id} from #{vs.object_id}. Parent - #{@ex}"
      @scalarStore=vs.scalarStore.hop_clone
      @cortegeStore=vs.cortegeStore.hop_clone
      @streamStore=vs.streamStore.hop_clone
    end

    def merge(vs)
      warn "Merge varstore #{object_id} with #{vs.object_id}. Parent - #{@ex}"
      @scalarStore.merge(vs.scalarStore.hop_clone)
      @cortegeStore.merge(vs.cortegeStore.hop_clone)
      @streamStore.merge(vs.streamStore.hop_clone)
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

    def getScalar(name)
      #warn ">>Read #{name} = #{@scalarStore[hopid][name]}"

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
      @streamStore[name].get
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
        #warn ">>SET #{name}: #{hopid} #{name}.#{key} = #{value}"
        @cortegeStore[name][key]=value
      }
    end

    def setSream(name, val)

      #!!!! TODO - only in debug version
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
      ret=''
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
      raise VarNotFound, "Var not found: #{name} in #{object_id} (#{@ex})\n[#{print_store}]\n"
    end

    def get(name)

      if @streamStore.has_key? name
        return @streamStore[name].get
      elsif @scalarStore.has_key? name
        return @scalarStore[name]
      elsif @cortegeStore.has_key? name
        return @cortegeStore[name]
      end
      raise VarNotFound, "Var not found: #{name} (#{@ex})\n[#{print_store}]\n"

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

    def testStream(name)
      return true if @streamStore.has_key? name
      false
    end

  end
end

