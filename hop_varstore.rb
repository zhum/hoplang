# TODO: deprecate all 'Cortege' things and remove them in future versions
module Hopsa
  class VarStor
    @scalarStore=Hash.new
    @cortegeStore=Hash.new
    @streamStore=Hash.new
    def self.addScalar(ex,name)
      hopid=ex.hopid
  #    warn "ADD_SCALAR: #{name} (#{hopid}/#{ex})\n"
      if @scalarStore[hopid].nil?
        @scalarStore[hopid]=Hash.new
      end
      @scalarStore[hopid][name]=''
    end
    def self.addStream(ex,name)
      hopid=ex.hopid
      if @streamStore[hopid].nil?
        @streamStore[hopid]=Hash.new
      end
      @streamStore[hopid][name]=HopPipe.new
    end
    def self.addCortege(ex,name)
      hopid=ex.hopid
      if @cortegeStore[hopid].nil?
        @cortegeStore[hopid]=Hash.new
      end
      @cortegeStore[hopid][name]={}
  #    warn ">>ADD #{name} (#{hopid})"
    end
    def self.getScalar(ex, name)
      hopid=searchIdForVar(@scalarStore,ex,name)
      warn ">>Read #{name} = #{@scalarStore[hopid][name]}"
      @scalarStore[hopid][name]
    end
    def self.getCortege(ex, name)
      hopid=searchIdForVar(@cortegeStore,ex,name)
      @cortegeStore[hopid][name]
    end
    def self.setScalar(ex, name, val)
      hopid=searchIdForVar(@scalarStore,ex,name)
      @scalarStore[hopid][name]=val
    end
    def self.setCortege(ex, name, val)
  #      warn ">>SET0: #{name} = #{val}"
      hopid=searchIdForVar(@cortegeStore,ex,name)
      val.each_pair{|key,value|
        warn ">>SET #{name}: #{hopid} #{name}.#{key} = #{value}"
        @cortegeStore[hopid][name][key]=value
      }
    end
    def self.getStream(ex, name)
      hopid=searchIdForVar(@streamStore,ex,name)
      @streamStore[hopid][name].get
    end
    def self.setScalar(ex, name, val)
      hopid=searchIdForVar(@streamStore,ex,name)
      @streamStore[hopid][name].put val
    end
    def self.canRead?(ex,name)
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
    def self.set(ex, name, val)
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
    def self.get(ex, name)
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
            raise VarNotFound "Var not found: #{name} (#{hopid}/#{ex})"
          end
        end
      end
    end
    # variables iterator
    def self.each_scalar(ex, &block)
      begin
        @scalarStore[ex.hopid].each &block
      rescue
      end
    end
    # variables iterator
    def self.each_cortege(ex, &block)
      begin
        @cortegeStore[ex.hopid].each &block
      rescue
      end
    end
    # variables iterator
    def self.each_stream(ex, &block)
      begin
        @streamStore[ex.hopid].each &block
      rescue
      end
    end
    def self.each(ex, &block)
      each_stream(ex,&block)
      each_cortege(ex,&block)
      each_scalar(ex,&block)
    end
    def self.testStream(ex, name)
      begin
        hopid=searchIdForVar(@streamStore,ex,name)
        return true
      rescue VarNotFound
        return false
      end
    end
    private
    # where search (hash), executor, varname
    def self.searchIdForVar(store,ex,name)
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

