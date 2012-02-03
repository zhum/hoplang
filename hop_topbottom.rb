module HOPSA
  def insert_up_sorted_pair(sort_value, value, sort_array, array)
    index=-1
    sort_array.each_with_index.map do |e, i|
      if sort_value <= e)
        array.insert(i, value)
        sort_array.insert(i,sort_value)
        return sort_array, array
      else
        next
      ens
    end
    array.push(value)
    sort_array.push(sort_value)
    return sort_array, array
  end

  class TopEachHopstance < EachHopstance
    # read next source line and write it into @source_var
    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless(line =~
        /top\s+(\d+)\s+(\S+)\s+in\s+(\S+)\s+by\s+(.*)\s+(\s+where\s+(.*))?/)

        raise SyntaxError.new(line)
      end

      hopstance=TopEachHopstance.new(parent)
#                           N,var,source, cond, where
      return hopstance.init($1,$2,$3,$4,$6),pos+1
    end

    def init(n,var,source,cond,where)
      @n=n
      @var=var
      @source=source
      @cond_expr  = HopExpr.parse_cond cond
      @where_expr = HopExpr.parse_cond where if where
      @top=[]
      self
    end


    def hop
      new_thread do
        while not (self.readSource).nil?
        end

        # now output top!
        @top.each do |var|
          varStore.set(@streamvar,var)
        end
        varStore(@streamvar,nil)
      end
    end

    def readSource
      value=varStore.get(@source)
      return nil if value.nil?

      # check top condition
      varStore.set(@var,value)
      topval=cond.eval(self)

      # insert in top
      @top_values,@top=insert_up_sorted_pair(topval,value,@top_values,@top)
      # delete oversized
      if @top.size>@n
        @top[@n..@n]=[]
        @topval[@n..@n]=[]
      end
      value
    end
  end

  class BottomEachHopstance < TopEachHopstance
    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless(line =~
        /bottom\s+(\d+)\s+(\S+)\s+in\s+(\S+)\s+by\s+(.*)\s+(\s+where\s+(.*))?/)

        raise SyntaxError.new(line)
      end

      hopstance=TopEachHopstance.new(parent)
#                           N,var,source, cond, where
      return hopstance.init($1,$2,$3,-$4,$6),pos+1
      #!!!! NOTE THE DIFFERENCE - cond is NEGATED!

    end
  end

end
