module Hopsa

  class GroupExecutor < Hopstance
    def initialize(parent,pipe,store,current_var,stream_var,chain,final,name=nil)
#      hop_warn "PAR: #{parent} -> #{name} #{object_id}"
      super(parent)
      @mainChain=chain.hop_clone
      @finalChain=final.hop_clone
      @current_var=current_var
      @stream_var=stream_var
      varStore.delStream(@stream_var)
      varStore.addCortege(@stream_var)
      @pipe=pipe
      @result=[]
      @name=name

      # rebase chains for local varstore
      @mainChain.executor=self
      @finalChain.executor=self
    end

    def to_s
      "#GroupExecutor:#{@name}"
    end

    def do_yield(hash)
      # push data into out pipe
      #dump_parents
#      hop_warn "GROUP EX YIELD #{@name}/#{object_id}: (#{hash.inspect})"
#      hop_warn "GROUP EX Y #{@parent.to_s}/#{@parent.object_id}"
      varStore.set(@stream_var,hash)
    end

    def hop
#      hop_warn "GROUP loop #{@name}"
      loop do
        var=@pipe.get
#        hop_warn "GROUP #{@name}: GOT #{var.inspect}"
        if(var.nil?)
#          hop_warn "GROUP #{@name} final start -> #{@stream_var}"
#          hop_warn ">> #{@finalChain.executor.varStore.print_store}"
          @finalChain.hop
          result=varStore.get(@stream_var)
#          hop_warn "GROUP #{@name} final end (#{result})"
#          hop_warn "final success #{varStore.print_store}"
          return result
        end
        varStore.set(@current_var,var)
#        hop_warn "GROUP MAIN #{@name} .....#{varStore.print_store}"
        @mainChain.hop
#        hop_warn "main success #{varStore.print_store}"
      end
    end
  end

  class GroupHopstance < Hopstance

    attr_reader :stream_var

    private
    @@global_count=0

    public

    def self.createNewRetLineNum(parent,text,pos)
      line,pos=Statement.nextLine(text,pos)

      raise UnexpectedEOF if line.nil?
      unless line =~
        /^(\S+)\s*=\s*group\s+(\S+)\s+by\s+(.+)\s+in\s+(\S+)(\s+where\s+(.*))?/

        raise SyntaxError.new(line)
      end

      stream_var,current_var,group_expr,source,where=$1,$2,$3,$4,$6

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
        hop_warn "GROUP DEFAULT Each"
        stream_hopstance=EachHopstance.new(parent)
      end

      local_stream=stream_var+"__group_#{@@global_count}"
      @@global_count+=1

      stream_hopstance.varStore.addStream(local_stream)
      stream_hopstance.varStore.addCortege(current_var)

      fake_text=["#","yield #{current_var}","end"]
      # !!! Important!
      # First element in fake_text MUST be... fake?
      # It will be ignored, so just let it be.

#      hop_warn "FAKE TEXT: #{fake_text.join(';')}"
      stream_hopstance.init(fake_text,0,local_stream,current_var,source,where)

      hop_warn "ADDED STREAM FOR GROUP: #{stream_hopstance} #{local_stream} #{current_var}"

      hopstance = GroupHopstance.new(stream_hopstance)
      hopstance.varStore.copyStreamFromParent(local_stream,stream_hopstance.varStore)
      hopstance.varStore.addCortege(current_var)
      parent.varStore.addStream(stream_var)
      hopstance.varStore.copyStreamFromParent(stream_var,parent.varStore)

      return hopstance.init(text,pos,stream_var,current_var,group_expr,source,where,stream_hopstance,local_stream)
    end

    def to_s
      "#GroupHopstance(#{@stream_var}<-#{@source})"
    end

    # ret: self, new_pos
    def init(text,pos,stream_var,current_var,group_expr,source,where,stream_hopstance,local_stream)
      @stream_var,@current_var,@source,@stream_hopstance,@local_stream=
        stream_var,current_var,source,stream_hopstance,local_stream

      # parse predicate expression, if any
      @where_expr = HopExpr.parse_cond where if where
      @group_expr = HopExpr.parse_cond group_expr
      #hop_warn @where_expr.inspect if @where_expr
      #hop_warn @group_expr.inspect

      @groups={}

      pos+=1
      hop_warn "GROUP: #{stream_var},#{current_var},#{group_expr},#{source},#{where}"
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
      hop_warn "START main chain (GROUP) #{@stream_var} <- #{@source} (#{@mainChain})"
      varStore.merge(@parent.varStore)
      @stream_hopstance.varStore.merge(varStore)
      @stream_hopstance.hop

#      new_thread do
        begin
          workers=[]
          while not (val=readSource).nil?
            if @where_expr && !@where_expr.eval(self)
              next
            end

            # calculate group
            group=@group_expr.eval(self)
#            hop_warn "GROUP EXPR #{@group_expr.inspect} = #{@group} (#{@current_var})"
            if @groups[group].nil?
              #create new group thread
              @groups[group]=HopPipe.new

              #start group processor
              workers << Thread.new {
              #parent,pipe,store,current_var,stream_var,chain,final
                hop_warn "GROUP THREAD #{Thread.current} start for #{group} (#{self})"
                executor=GroupExecutor.new(self,@groups[group],varStore,
                                       @current_var,@stream_var,
                                       @mainChain,@finalChain,group)
#                hop_warn "GROUP THREAD #{t} executor for #{group} #{executor}"
                result=executor.hop
                Thread.current['result']=result
#                hop_warn "GROUP THREAD #{Thread.current} end: #{result.inspect}"
              }
            end

            @groups[group].put(val)
#            hop_warn "PUT #{group} #{val.inspect}"
          end #while read source

          # process final section
#          hop_warn "START GROUP final chain (#{@finalChain})"
          #hop_warn @groups.inspect
          @groups.each_pair do |name,pipe|
            hop_warn "GROUP thread finishing #{name}"
            pipe.put(nil)
          end

          workers.each do |t|
#            hop_warn "Try to join #{t} (#{t.status})"
            fin=t.join
#            hop_warn "GROUP Thread #{t} joined (#{fin}/#{t.status})"
            #put result to output stream
            a=[]
            a<< t['result']
#            hop_warn "Result: #{a.inspect}"
            a.each {|val| do_yield val}
          end
#          hop_warn "GROUP FINISHED!\n-------------------------------"
          # write EOF to out stream
          do_yield(nil)
        rescue => e
          hop_warn "Exception in #{@stream_var} <- #{@source} (#{@mainChain}: #{e}. "+e.backtrace.join("\t\n")
        end
#      end #~Thread
    end

    def do_yield(hash)
      # push data into out pipe
#      hop_warn "YYYY1 (#{hash.inspect})"
      varStore.set(@stream_var,hash)
    end

    # read next source line and write it into @source_var
    def readSource
      value=varStore.get(@local_stream)
#      hop_warn "GROUP READED from #{@local_stream} #{value.inspect}\n#{varStore.print_store}"

      varStore.set(@current_var, value)
#      group=@group_expr.eval(self)
#      hop_warn "#{@current_var}= #{@group_expr.inspect} = #{group.inspect}"
      value
    end
  end

end
