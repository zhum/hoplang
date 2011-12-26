# TODO: deprecate all 'Cortege' things and remove them in future versions
module Hopsa
  class VarStore
    @scalarStore=Hash.new
    @cortegeStore=Hash.new
    @streamStore=Hash.new

    protected
    attr_reader :scalarStore, :streamStore, :cortegeStore
    
    public
    
    def initVarStore(vs=nil)
      if vs.nil? then
        @myVarStore=VarStore.new(nil)
      else
        @myVarStore=copy(vs)
      end
    end
    
    def initialize(ex)
      warn "New varstore #{object_id}. Parent - #{ex}"
      @ex=ex
      @scalarStore=Hash.new
      @cortegeStore=Hash.new
      @streamStore=Hash.new
    end
    
    def copy(vs)
      warn "Copy varstore #{object_id} from #{vs.object_id}. Parent - #{@ex}"
      @scalarStore=vs.scalarStore
      @cortegeStore=vs.cortegeStore
      @streamStore=vs.streamStore
    end    
    
    def addScalar(name)
      hopid=@ex.hopid
      warn "ADD_SCALAR: #{name} to #{object_id}/#{@ex}"
      if @scalarStore[hopid].nil?
        @scalarStore[hopid]=Hash.new
      end
      @scalarStore[hopid][name]=''
    end
    def addStream(name)
      hopid=@ex.hopid
      warn "ADD_STREAM: #{name} to #{object_id}/#{@ex}"
      if @streamStore[hopid].nil?
        @streamStore[hopid]=Hash.new
      end
      @streamStore[hopid][name]=HopPipe.new
    end
    def addCortege(name)
      hopid=@ex.hopid
      if @cortegeStore[hopid].nil?
        @cortegeStore[hopid]=Hash.new
      end
      @cortegeStore[hopid][name]={}
  #    warn ">>ADD #{name} (#{hopid})"
    end
    def getScalar(name)
      hopid=searchIdForVar(@scalarStore,name)
      warn ">>Read #{name} = #{@scalarStore[hopid][name]}"
      @scalarStore[hopid][name]
    end
    def getCortege(name)
      hopid=searchIdForVar(@cortegeStore,name)
      @cortegeStore[hopid][name]
    end
    def setScalar(name, val)
      hopid=searchIdForVar(@scalarStore,name)
      @scalarStore[hopid][name]=val
    end
    def setCortege(name, val)
  #      warn ">>SET0: #{name} = #{val}"
      hopid=searchIdForVar(@cortegeStore,name)
      val.each_pair{|key,value|
        warn ">>SET #{name}: #{hopid} #{name}.#{key} = #{value}"
        @cortegeStore[hopid][name][key]=value
      }
    end
    def getStream(name)
      hopid=searchIdForVar(@streamStore,name)
      @streamStore[hopid][name].get
    end
    def setScalar(name, val)
      hopid=searchIdForVar(@streamStore,name)
      @streamStore[hopid][name].put val
    end
    def canRead?(name)
      begin
        hopid=searchIdForVar(@streamStore,name)
        not @streamStore[hopid][name].empty?
      rescue VarNotFound
        begin
          hopid=searchIdForVar(@cortegeStore,name)
          true
        rescue VarNotFound
          begin
            hopid=searchIdForVar(@scalarStore,name)
            true
          rescue VarNotFound
            false
          end
        end
      end
    end
    def set(name, val)
      begin
        hopid=searchIdForVar(@streamStore,name)
        @streamStore[hopid][name].put val
      rescue VarNotFound
        begin
          hopid=searchIdForVar(@cortegeStore,name)
          @cortegeStore[hopid][name]=val
        rescue VarNotFound
          hopid=searchIdForVar(@scalarStore,name)
          @scalarStore[hopid][name]=val
        end
      end
    end
    def get(name)
      
      begin
        hopid=searchIdForVar(@streamStore,name)
        return  @streamStore[hopid][name].get
      rescue VarNotFound
        begin
          hopid=searchIdForVar(@cortegeStore,name)
          return @cortegeStore[hopid][name]
        rescue VarNotFound
          begin
            hopid=searchIdForVar(@scalarStore,name)
  #          warn "#{hopid}."
            return @scalarStore[hopid][name]
          rescue
            raise VarNotFound, "Var not found: #{name} (#{hopid}/#{@ex})"
          end
        end
      end
    end
    # variables iterator
    def each_scalar(&block)
      begin
        @scalarStore[@ex.hopid].each &block
      rescue
      end
    end
    # variables iterator
    def each_cortege(&block)
      begin
        @cortegeStore[@ex.hopid].each &block
      rescue
      end
    end
    # variables iterator
    def each_stream(&block)
      begin
        @streamStore[@ex.hopid].each &block
      rescue
      end
    end
    def each(&block)
      each_stream(&block)
      each_cortege(&block)
      each_scalar(&block)
    end
    def testStream(name)
      begin
        hopid=searchIdForVar(@streamStore,name)
        return true
      rescue VarNotFound
        return false
      end
    end
    private
    # where search (hash), executor, varname
    def searchIdForVar(store,name)
      ex=@ex
      while not ex.nil? do;
        if not store[ex.hopid].nil?
  #        warn "Trace: #{name} #{ex.hopid} = #{store[ex.hopid][name]} "
          if not store[ex.hopid][name].nil?
  #          warn "YE!"
            return ex.hopid
          end
        end
        ex=ex.parent
      end
      #warn "SEARCH FAIL #{name} in #{ex}"
      raise VarNotFound.new "NOT FOUND #{name} in #{ex}"
    end
  end
end

