module Hopsa
  # Read several sources...
  class StreamDBDriver <HopsaDBDriver

    # check, if we can read this source
    def self.test(context, source)
      begin
        context.varStore.test_stream(source)
      rescue VarNotFound
        return false
      end
      true
    end


    def initialize(parent, source, current_var, where)
      super(parent, source, current_var, where)
      hop_warn "STREAM #{source.inspect}"
#      @source=source
#      @current_var=current_var
#      @where=where
      @where_expr = where.nil? ? nil : HopExpr.parse(where)
    end

    # read next source line
    def readSource
      loop do
#        hop_warn "Stream read (#{@source})!"
        val=@parent.varStore.getStream(@source)
#        hop_warn "Stream readed (#{@source} = #{val.inspect})"
        return nil if val.nil?
        if @where_expr
          return val if @where_expr.eval(@parent)
        else
          return val
        end
      end
    end
  end
end
