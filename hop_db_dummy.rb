module Hopsa
  # DUMMY DATABASE ACCESS CLASS
  class CSVDriver <HopsaDBDriver
    # read next source line
    def readSource
      if @source_in.nil?
        @source_in = open @source
        # fields titles
        head=@source_in.readline.strip
        @heads=head.split(/\s*,\s*/)
      end

      begin
        line=@source_in.readline.strip
        datas=line.split(/\s*,\s*/)

        i=0
        value={}
        @heads.each {|h|
          value[h]=datas[i]
          i+=1
        }
        # now store variable!
        #varStore.set(@current_var, value)
        return value
      rescue EOFError
        hop_warn "EOF.....\n"
        #varStore.set(@current_var, nil)
        return nil
      end
        line
    end
  end

end
