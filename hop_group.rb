module Hopsa

  class GroupExecutor < Hopstance
    def initialize(parent,pipe,store,current_var,stream_var,chain,final,name=nil)
      super(parent)
      @mainChain=chain
      @finalChain=final
      @current_var=current_var
      @stream_var=stream_var
      varStore.delStream(@stream_var)
      varStore.addCortege(@stream_var)
      @pipe=pipe
      @result=[]
      @name=name

      # rebase chins for local varstore
      @mainChain.executor=self
      @finalChain.executor=self
    end

    def hop
      hop_warn "GROUP loop #{@name}"
      loop do
        var=@pipe.get
        hop_warn "GROUP: GOT #{var.inspect}"
        if(var.nil?)
          hop_warn "GROUP #{@name} final start"
          @finalChain.hop
          hop_warn "-----------"
          result=varStore.get(@stream_var)
          hop_warn "GROUP #{@name} final end (#{result})"
          return result
        end
        varStore.set(@current_var,var)
#        hop_warn ".....#{varStore.print_store}"
        @mainChain.hop
        hop_warn "main success"
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
          hop_warn "No such driver: #{type}!"
          stream_hopstance=EachHopstance.new(parent)
        end
      else
        hop_warn "DEFAULT Each"
        stream_hopstance=EachHopstance.new(parent)
      end

      local_stream=streamvar+"__group_#{@@global_count}"
      @@global_count+=1

      stream_hopstance.varStore.addStream(local_stream)
      stream_hopstance.varStore.addCortege(current_var)

      fake_text=["#debug 1","yield #{current_var}","end"]
      hop_warn "FAKE TEXT: #{fake_text.join(';')}"
      stream_hopstance.init(fake_text,0,local_stream,current_var,source,where)

      hop_warn "ADDED STREAM FOR GROUP: #{stream_hopstance} #{local_stream} #{current_var}"

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
      #hop_warn @where_expr.inspect if @where_expr
      #hop_warn @group_expr.inspect

      @groups={}

      pos+=1
      hop_warn ":: #{text[pos]}"
      hop_warn "GROUP: #{streamvar},#{current_var},#{group_expr},#{source},#{where}"
      # now create execution chains for body and final sections
      begin
        while true
          statement,pos=Statement.createNewRetLineNum(self,text,pos)
          @mainChain.add statement
        end
      rescue SyntaxError
        line,pos=Statement.nextLine(text,pos)
        hop_warn ">>#{line}<<"
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
      hop_warn "START main chain (GROUP) #{@streamvar} <- #{@source} (#{@mainChain})"
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
            #hop_warn "GROUP EXPR #{@group_expr.inspect} = #{@group} (#{@current_var})"
            if @groups[group].nil?
              #create new group thread
              @groups[group]=HopPipe.new

              #start group processor
              workers << Thread.new {
              #parent,pipe,store,current_var,stream_var,chain,final
                hop_warn "GROUP THREAD #{Thread.current} start for #{group}"
                executor=GroupExecutor.new(self,@groups[group],varStore,
                                       @current_var,@streamvar,
                                       @mainChain,@finalChain,group)
#                hop_warn "GROUP THREAD #{t} executor for #{group} #{executor}"
                result=executor.hop
                Thread.current['result']=result
                hop_warn "GROUP THREAD #{Thread.current} end: #{result.inspect}"
              }
            end

            @groups[group].put(val)
            hop_warn "PUT #{group} #{val.inspect}"
          end #while read source

          # process final section
          hop_warn "START GROUP final chain (#{@finalChain})"
          #hop_warn @groups.inspect
          @groups.each_pair do |name,pipe|
            hop_warn "GROUP thread finishing #{name}"
            pipe.put(nil)
          end

          workers.each do |t|
            hop_warn "Try to join #{t} (#{t.status})"
            fin=t.join
            hop_warn "GROUP Thread #{t} joined (#{fin}/#{t.status})"
            #put result to output stream
            t['result'].each {|val| do_yield val}
          end
          hop_warn "GROUP FINISHED!\n-------------------------------"
          # write EOF to out stream
          do_yield(nil)
        rescue => e
          hop_warn "Exception in #{@streamvar} <- #{@source} (#{@mainChain}: #{e}. "+e.backtrace.join("\t\n")
        end
      end #~Thread
    end

    def do_yield(hash)
      # push data into out pipe
      #hop_warn "YYYY1 (#{hash.inspect})"
      varStore.set(@streamvar,hash)
    end

    # read next source line and write it into @source_var
    def readSource
      value=varStore.get(@local_stream)
      #hop_warn "GROUP READED from #{@local_stream} #{value.inspect}"

      varStore.set(@current_var, value)
#      group=@group_expr.eval(self)
#      hop_warn "#{@current_var}= #{@group_expr.inspect} = #{group.inspect}"
      value
    end
  end

end
