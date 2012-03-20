module Hopsa
  def insert_up_sorted_pair(sort_value, value, sort_array, array)
    index=-1
    sort_array.each_with_index.map do |e, i|
      if sort_value <= e
        array.insert(i, value)
        sort_array.insert(i,sort_value)
        return sort_array, array
      else
        next
      end
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
        /^\s*(\S+)\s*=\s*top\s+(.+)\s+(\S+)\s+in\s+(\S+)\s+by\s+(.*)(\s+where\s+(.*))?/)
#             OUT,             N,       var,        source, cond, where
#              1               2         3             4      5    7
        raise SyntaxError.new(line)
      end

      hopstance=TopEachHopstance.new(parent)

      hopstance.varStore.addScalar($3)
      parent.varStore.addStream($1)
      hopstance.varStore.copyStreamFromParent($1,parent.varStore)

      return hopstance.init($1,$2,$3,$4,$5,$7),pos+1
    end

    def init(out,n,var,source,cond,where)
      @n=HopExpr.parse n
      @current_var=var
      @source=source
      @streamvar=out
#      hop_warn "TOP Condition: #{cond}"
      @cond_expr  = HopExpr.parse_cond cond
      @where_expr = HopExpr.parse_cond where if where
      @top=[]
      @top_values=[]

      self
    end

    def to_s
      "#TopHopstance(#{@stream}<(#{@current_var})-#{@source})"
    end

    def hop
      varStore.merge(@parent.varStore)
      new_thread 'topbottom' do
        hop_warn varStore.print_store
        while not (self.readSource).nil?
        end

        # now output top!
        @top.each do |var|
          varStore.set(@streamvar,var)
        end
        varStore.set(@streamvar,nil)
      end
    end

    def readSource
      value=varStore.get(@source)
      return nil if value.nil?

      # check top condition
      varStore.set(@current_var,value)
      topval=@cond_expr.eval(self)

      # insert in top
      @top_values,@top=insert_up_sorted_pair(topval,value,@top_values,@top)
      # delete oversized
      n=@n.eval(self).to_i
      if @top.size > n
        @top[n..n]=[]
        @top_values[n..n]=[]
      end
      value
    end
  end

  class BottomEachHopstance < TopEachHopstance
    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless(line =~
        /^\s*(\S+)\s*=\s*bottom\s+(.+)\s+(\S+)\s+in\s+(\S+)\s+by\s+(.*)(\s+where\s+(.*))?/)

        raise SyntaxError.new(line)
      end

      hopstance=TopEachHopstance.new(parent)

      hopstance.varStore.addScalar($3)
      parent.varStore.addStream($1)
      hopstance.varStore.copyStreamFromParent($1,parent.varStore)
#                           out,N,var,source, cond, where
      return hopstance.init($1,$2,$3,$4,-($5.to_i),$7),pos+1
      #!!!! NOTE THE DIFFERENCE - cond is NEGATED!

    end

    def to_s
      "#BottomHopstance(#{@stream}<(#{@current_var})-#{@source})"
    end

  end

end
