# TODO: deprecate all 'Cortege' things and remove them in future versions
module Hopsa

  module Vars
    def var_get(var)
      @myVarStore.get(self,var)
    end

    def var_set(var,val)
      @myVarStore.set(self,var,val)
    end
    
    def initVarStore(vs=nil)
      @myVarStore = VarStor.new
      unless vs.nil?
        @myVarStore.copyFrom vs
      end
    end
    
    def addScalar(ex,name)
      @myVarStore.addScalar(ex,name)
    end

    def addStream(ex,name)
      @myVarStore.addStream(ex,name)
    end

    def addCortege(ex,name)
      @myVarStore.addCortege(ex,name)
    end

    def testScalar(ex,name)
      @myVarStore.testScalar(ex,name)
    end

    def testStream(ex,name)
      @myVarStore.testStream(ex,name)
    end

    def testCortege(ex,name)
      @myVarStore.testCortege(ex,name)
    end

    protected

    # for the name to be correct
    def varStore
      @myVarStore
    end
  end
  
  
  class VarStor

    protected
      attr_reader :scalarStore, :cortegeStore, :streamStore
      
    public
    
    def initialize()
      @scalarStore=Hash.new
      @cortegeStore=Hash.new
      @streamStore=Hash.new
    end
    
    def copyFrom(vs)
      @scalarStore=vs.scalarStore
      @cortegeStore=vs.cortegeStore
      @streamStore=vs.streamStore
    end

    def addScalar(ex,name)
      hopid=ex.hopid
  #    warn "ADD_SCALAR: #{name} (#{hopid}/#{ex})\n"
      if @scalarStore[hopid].nil?
        @scalarStore[hopid]=Hash.new
      end
      @scalarStore[hopid][name]=''
    end
    def addStream(ex,name)
      hopid=ex.hopid
      if @streamStore[hopid].nil?
        @streamStore[hopid]=Hash.new
      end
      @streamStore[hopid][name]=HopPipe.new
    end
    def addCortege(ex,name)
      hopid=ex.hopid
      if @cortegeStore[hopid].nil?
        @cortegeStore[hopid]=Hash.new
      end
      @cortegeStore[hopid][name]={}
  #    warn ">>ADD #{name} (#{hopid})"
    end
    def getScalar(ex, name)
      hopid=searchIdForVar(@scalarStore,ex,name)
      warn ">>Read #{name} = #{@scalarStore[hopid][name]}"
      @scalarStore[hopid][name]
    end
    def getCortege(ex, name)
      hopid=searchIdForVar(@cortegeStore,ex,name)
      @cortegeStore[hopid][name]
    end
    def setScalar(ex, name, val)
      hopid=searchIdForVar(@scalarStore,ex,name)
      @scalarStore[hopid][name]=val
    end
    def setCortege(ex, name, val)
  #      warn ">>SET0: #{name} = #{val}"
      hopid=searchIdForVar(@cortegeStore,ex,name)
      val.each_pair{|key,value|
        warn ">>SET #{name}: #{hopid} #{name}.#{key} = #{value}"
        @cortegeStore[hopid][name][key]=value
      }
    end
    def getStream(ex, name)
      hopid=searchIdForVar(@streamStore,ex,name)
      @streamStore[hopid][name].get
    end
    def setScalar(ex, name, val)
      hopid=searchIdForVar(@streamStore,ex,name)
      @streamStore[hopid][name].put val
    end
    def canRead?(ex,name)
      begin
        hopid=searchIdForVar(@streamStore,ex,name)
        not @streamStore[hopid][name].empty?
      rescue VarNotFound
        begin
          hopid=searchIdForVar(@cortegeStore,ex,name)
          true
        rescue VarNotFound
          begin
            hopid=searchIdForVar(@scalarStore,ex,name)
            true
          rescue VarNotFound
            false
          end
        end
      end
    end
    def set(ex, name, val)
      begin
        hopid=searchIdForVar(@streamStore,ex,name)
        @streamStore[hopid][name].put val
      rescue VarNotFound
        begin
          hopid=searchIdForVar(@cortegeStore,ex,name)
          @cortegeStore[hopid][name]=val
        rescue VarNotFound
          hopid=searchIdForVar(@scalarStore,ex,name)
          @scalarStore[hopid][name]=val
        end
      end
    end
    def get(ex, name)
      begin
        hopid=searchIdForVar(@streamStore,ex,name)
        return  @streamStore[hopid][name].get
      rescue VarNotFound
        begin
          hopid=searchIdForVar(@cortegeStore,ex,name)
          return @cortegeStore[hopid][name]
        rescue VarNotFound
          begin
            hopid=searchIdForVar(@scalarStore,ex,name)
  #          warn "#{hopid}."
            return @scalarStore[hopid][name]
          rescue
            raise VarNotFound.new "Var not found: #{name} (#{hopid}/#{ex})"
          end
        end
      end
    end
    # variables iterator
    def each_scalar(ex, &block)
      begin
        @scalarStore[ex.hopid].each &block
      rescue
      end
    end
    # variables iterator
    def each_cortege(ex, &block)
      begin
        @cortegeStore[ex.hopid].each &block
      rescue
      end
    end
    # variables iterator
    def each_stream(ex, &block)
      begin
        @streamStore[ex.hopid].each &block
      rescue
      end
    end
    def each(ex, &block)
      each_stream(ex,&block)
      each_cortege(ex,&block)
      each_scalar(ex,&block)
    end
    def testStream(ex, name)
      begin
        hopid=searchIdForVar(@streamStore,ex,name)
        return true
      rescue VarNotFound
        return false
      end
    end
    private
    # where search (hash), executor, varname
    def searchIdForVar(store,ex,name)
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
  #    warn "SEARCH FAIL #{name}"
      raise VarNotFound.new name
    end
  end
end

