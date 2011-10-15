module Hopsa
  # Read several sources...
  class SplitEachHopstance <EachHopstance

    def initialize(parent, sources)
      super(parent)
      warn "SPLIT #{sources.size}"
      @sources=sources
    end

    def init(text,pos,streamvar,current_var,source,where)
      @hopsources=Array.new
      @streamvar,@current_var,@source=streamvar,current_var,source
      pos2=0

      @sources.each_with_index{|s,i|

        # deep clone...
        text_s=Marshal.load(Marshal.dump(text))

        #change 'each' statement...
        if streamvar=='' then
          text_s[pos]=''
        else
          text_s[pos]="#{streamvar}__#{i}="
        end
        text_s[pos]+="each #{current_var} in #{s[:name]}"
        text_s[pos]+=" where #{where}" if where !=''

        hopstance,pos2=EachHopstance.createNewRetLineNum(self,text_s,pos)
        @hopsources << hopstance
      }
      @current_source=-1
      return self,pos2+1
    end

#    def hop
#      warn "SplitHOP"
#    end

    # read next source line and write it into @source_var
    def readSource
      saved_source=@current_source

      begin
        @current_source+=1
        @current_source=0 if @current_source>=@hopsources.size

#        warn "->RRRRRRRRRRRRRRRRRRRRRR #{@hopsources[@current_source]}"

        #!!!! Must be deleted on thread version!!!
        @hopsources[@current_source].hop

#        warn "<-RRRRRRRRRRRRR #{@current_source}/#{@current_var}: #{@hopsources[@current_source]}(#{@hopsources[@current_source].streamvar})"
        if VarStor.canRead?(@hopsources[@current_source],
                            @hopsources[@current_source].streamvar) then
          value=VarStor.get(@hopsources[@current_source],
                            @hopsources[@current_source].streamvar)
          #@outPipe.put value
          VarStor.set(self, @streamvar, value)
#          warn "R_R #{value}"
          return value
        end
#        warn "RR #{saved_source} #{@current_source}"
      end while saved_source!=@current_source
      return nil
    end
  end
end

