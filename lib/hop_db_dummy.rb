# coding: utf-8
module Hopsa
  # DUMMY DATABASE ACCESS CLASS
  class CSVDriver <HopsaDBDriver

    def initialize(parent, source, current_var, where)
      super
      dir='.'
      begin
        dir = Config['dbmap']['dummy']['dir']
      rescue
      end
      @dir=Pathname.new(dir)
    end
    # read next source line
    def readSource
      if @source_in.nil?
        @source_in = open @dir+Pathname.new(@source)
        # fields titles
        head=@source_in.readline.strip
        @heads=head.split(/\s*,\s*/)
        @hoplang_cols_order = @heads.join ','
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
        value['__hoplang_cols_order'] = @hoplang_cols_order
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
