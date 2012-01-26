module Hopsa

  class GroupExecutor < Hopstance
    def initialize(parent,pipe,store,current_var,stream_var,chain,final)
      super(parent)
      varStore.merge(parent.varStore)
      @mainChain=chain
      @finalChain=final
      @current_var=current_var
      @stream_var=stream_var
      varStore.addCortege(@stream_var)
      @pipe=pipe
      @result=[]
    end

    def do_yield(hash)
      warn "GROUP OUT: #{hash.inspect}"
      @result.push hash
    end

    def hop
      warn "GROUP loop #{@current_var}"
      loop do
        var=@pipe.get
        warn "GROUP: GOT #{var.inspect}"
        if(var.nil?)
          @finalChain.hop
          return @result
        end
        varStore.set(@current_var,var)
#        warn ".....#{varStore.print_store}"
        @mainChain.hop
        warn "main success"
      end
    end
  end

  class GroupHopstance < Hopstance

    attr_reader :streamvar

    private
    @@global_count=0

    public

    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless line =~
        /^(\S+)\s*=\s*group\s+(\S+)\s+by\s+(.+)\s+from\s+(\S+)(\s+where\s+(.*))?/

        raise SyntaxError.new(line)
      end

      streamvar,current_var,group_expr,source,where=$1,$2,$3,$4,$6

      cfg_entry = Config["db_type_#{source}"]
      src=Config.varmap[source]
      type=src.nil? ? nil : src['type']
      if(parent.varStore.testStream(source)) then
        stream_hopstance=StreamEachHopstance.new(parent)
      elsif(type=='csv') then
        stream_hopstance=MyDatabaseEachHopstance.new(parent)
      elsif(@@hoplang_databases.include? type)
        typename=(type.capitalize+'Hopstance').to_class
        stream_hopstance = typename.new parent, source
      elsif(type=='split') then
        i=1
        types_list=Array.new
        while name=Config["n_#{i}_#{source}"] do
          types_list << {:n => i, :name => name}
          i+=1
        end
        stream_hopstance=SplitEachHopstance.new(parent, types_list)
      elsif(not type.nil?) then
        begin
          stream_hopstance=Object.const_get(type+'Hopstance').new(parent)
        rescue NameError
          warn "No such driver: #{type}!"
          stream_hopstance=EachHopstance.new(parent)
        end
      else
        warn "DEFAULT Each"
        stream_hopstance=EachHopstance.new(parent)
      end

      local_stream=streamvar+"__group_#{@@global_count}"
      @@global_count+=1

      stream_hopstance.varStore.addStream(local_stream)
      stream_hopstance.varStore.addCortege(current_var)

      fake_text=["#debug 1","yield #{current_var}","end"]
      warn "FAKE TEXT: #{fake_text.join(';')}"
      stream_hopstance.init(fake_text,0,local_stream,current_var,source,where)

      warn "ADDED STREAM FOR GROUP: #{stream_hopstance} #{local_stream} #{current_var}"

      hopstance = GroupHopstance.new(stream_hopstance)
      hopstance.varStore.copyStreamFromParent(local_stream,stream_hopstance.varStore)
      hopstance.varStore.addCortege(current_var)
      parent.varStore.addStream(streamvar)
      hopstance.varStore.copyStreamFromParent(streamvar,parent.varStore)

      return hopstance.init(text,pos,streamvar,current_var,group_expr,source,where,stream_hopstance,local_stream)
    end

    def to_s
      "#GroupHopstance(#{@streamvar}<-#{@source})"
    end

    # ret: self, new_pos
    def init(text,pos,streamvar,current_var,group_expr,source,where,stream_hopstance,local_stream)
      @streamvar,@current_var,@source,@stream_hopstance,@local_stream=
        streamvar,current_var,source,stream_hopstance,local_stream

      # parse predicate expression, if any
      @where_expr = HopExpr.parse_cond where if where
      @group_expr = HopExpr.parse_cond group_expr
      #warn @where_expr.inspect if @where_expr
      #warn @group_expr.inspect

      @groups={}

      pos+=1
      warn ":: #{text[pos]}"
      warn "GROUP: #{streamvar},#{current_var},#{group_expr},#{source},#{where}"
      # now create execution chains for body and final sections
      begin
        while true
          statement,pos=Statement.createNewRetLineNum(self,text,pos)
          @mainChain.add statement
        end
      rescue SyntaxError
        line,pos=Statement.nextLine(text,pos)
        warn ">>#{line}<<"
        if line == 'final'
          # process final section!
          pos+=1
          begin
            while true
              hopstance,pos=Statement.createNewRetLineNum(self,text,pos)
              @finalChain.add hopstance
            end
          rescue SyntaxError
            line,pos=Statement.nextLine(text,pos)
            if line == 'end'
              return self,pos+1
            end
          end
      elsif line == 'end'
          return self,pos+1
        end
      end
      raise SyntaxError.new(line)
    end

    def hop
      warn "START main chain (GROUP) #{@streamvar} <- #{@source} (#{@mainChain})"
      varStore.merge(@parent.varStore)
      @stream_hopstance.hop

      new_thread do
        begin
          workers=[]
          while not (val=readSource).nil?
            if @where_expr && !@where_expr.eval(self)
              #puts @where_expr.eval(self)
              next
            end

            # calculate group
            group=@group_expr.eval(self)
            #warn "GROUP EXPR #{@group_expr.inspect} = #{@group} (#{@current_var})"
            if @groups[group].nil?
              #create new group thread
              warn "New GROUP: #{group}"
              @groups[group]=HopPipe.new

              #start group processor
              t=Thread.new do
              #parent,pipe,store,current_var,stream_var,chain,final
                exec=GroupExecutor.new(self,@groups[group],varStore,
                                       @current_var,@streamvar,@mainChain,@finalChain)
                warn "GROUP THREAD0 for #{group} - #{exec}"
                result=exec.hop
                warn "GROUP THREAD1: #{result}"
                Thread.current['result']=result
              end
              workers.push t
            end

            @groups[group].put(val)
          end #while read source

          # process final section
          warn "START GROUP final chain (#{@finalChain})"
          #warn @groups.inspect
          @groups.each do |name,pipe|
            warn "Finish #{name}"
            pipe.put(nil)
          end

          workers.each do |t|
            fin=t.join
            warn "GROUP Thread #{t} joined (#{t.status})"
            #put result to output stream
            t['result'].each {|val| do_yield val}
          end
          warn "GROUP FINISHED!\n-------------------------------"
          # write EOF to out stream
          do_yield(nil)
        rescue => e
          warn "Exception in #{@streamvar} <- #{@source} (#{@mainChain}: #{e}. "+e.backtrace.join("\t\n")
        end
      end #~Thread
    end

    def do_yield(hash)
      # push data into out pipe
      warn "YYYY1 (#{hash.inspect})"
      varStore.set(@streamvar,hash)
    end

    # read next source line and write it into @source_var
    def readSource
      value=varStore.get(@local_stream)
      warn "GROUP READED from #{@local_stream} #{value.inspect}"

      varStore.set(@current_var, value)
#      group=@group_expr.eval(self)
#      warn "#{@current_var}= #{@group_expr.inspect} = #{group.inspect}"
      value
    end
  end

end
