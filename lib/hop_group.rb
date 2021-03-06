# coding: utf-8
module Hopsa

  class GroupExecutor < Hopstance
    def initialize(parent,pipe,store,current_var,stream_var,init,chain,final,name=nil)
#      hop_warn "PAR: #{parent} -> #{name} #{object_id}"
      super(parent)
      @initChain=init.hop_clone
      @mainChain=chain.hop_clone
      @finalChain=final.hop_clone
      @current_var=current_var
      @stream_var='__group_var_'+object_id.to_s #stream_var
#      varStore.delStream(@stream_var)
      varStore.addCortege(@stream_var)
      @pipe=pipe
      @name=name

      # rebase chains for local varstore
      @mainChain.executor=self
      @finalChain.executor=self
    end

    def to_s
      "#GroupExecutor:#{@name}"
    end

    def do_yield(hash)
      Thread.current['result'] << hash
    end

    def hop
      var=nil
      @initChain.hop
      loop do
        var=@pipe.get
#        hop_warn "GROUP #{@name}: GOT #{var.inspect}"
        if(var.nil?)
          hop_warn "GROUP #{@name} final start -> #{@stream_var}"
          @finalChain.executor=self
          @finalChain.hop
          result=varStore.get(@stream_var)
          return result
        end
        varStore.set(@current_var,var)
        @mainChain.hop
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
      source_driver=initSourceDriver(parent, source, current_var, where)

#      cfg_entry = Config["db_type_#{source}"]
#      src=Config.varmap[source]
#      type=src.nil? ? nil : src['type']
#      if(parent.varStore.test_stream(source)) then
#        stream_hopstance=StreamEachHopstance.new(parent)
#      elsif(type=='csv') then
#        stream_hopstance=MyDatabaseEachHopstance.new(parent)
#      elsif(@@hoplang_databases.include? type)
#        typename=(type.capitalize+'Hopstance').to_class
#        stream_hopstance = typename.new parent, source, current_var, where
#      elsif(type=='split') then
#        i=1
#        types_list=Array.new
#        while name=Config["n_#{i}_#{source}"] do
#          types_list << {:n => i, :name => name}
#          i+=1
#        end
#        stream_hopstance=SplitEachHopstance.new(parent, types_list)
#      elsif(not type.nil?) then
#        begin
#          stream_hopstance=Object.const_get(type+'Hopstance').new(parent)
#        rescue NameError
#          hop_warn "No such driver: #{type}!"
#          stream_hopstance=EachHopstance.new(parent)
#        end
#      else
#        hop_warn "GROUP DEFAULT Each"
#        stream_hopstance=EachHopstance.new(parent)
#      end

      stream_hopstance=EachHopstance.new(parent)
      stream_hopstance.varStore.addScalar(current_var)
      parent.varStore.addStream(stream_var)
      #stream_hopstance.varStore.copyStreamFromParent(stream_var,parent.varStore)

      local_stream=stream_var+"__group_#{@@global_count}"
      @@global_count+=1

      stream_hopstance.varStore.addStream(local_stream)
      stream_hopstance.varStore.addCortege(current_var)

      fake_text=["#","yield #{current_var}","end"]
      # !!! Important!
      # First element in fake_text MUST be... fake?
      # It will be ignored, so just let it be.

#      hop_warn "FAKE TEXT: #{fake_text.join(';')}"
      stream_hopstance.init(fake_text,0,local_stream,current_var,source_driver,where)

      hop_warn "ADDED STREAM FOR GROUP: #{stream_hopstance} #{local_stream} #{current_var}"

      #
      #  Now prepare GROUPING hopstance!
      #
      hopstance = GroupHopstance.new(stream_hopstance)
      #hopstance.varStore.copyStreamFromParent(local_stream,stream_hopstance.varStore)
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
      @threads={}

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
              handle_agg_in_statement hopstance
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
      workers={}
      pipes={}
      @new_mutex=Mutex.new

      new_thread self.to_s do
        begin
          while not (val=readSource).nil?
            if @where_expr && !@where_expr.eval(self)
              next
            end

            # calculate group
            group=@group_expr.eval(self)
#            hop_warn "GROUP EXPR #{@group_expr.inspect} = #{@group} (#{@current_var})"
            if pipes[group].nil?
              #create new group thread
              pipe=HopPipe.new
              pipes[group]=pipe

              #start group processor
              main_thread=Thread.current
              main_thread['barrier']=true
              t= Thread.new do
                my_group=nil
                my_pipe=nil
                executor=nil
                  my_group=group
                  Thread.current['input']=[]
                  my_pipe=pipes[group]
                  hop_warn "GROUP THREAD start #{my_group} #{Thread.current} (#{self})"
                  #parent,pipe,store,current_var,stream_var,chain,final
                  executor=GroupExecutor.new(self,my_pipe,varStore,
                                         @current_var,@stream_var,
                                         @initChain,@mainChain,@finalChain,my_group)
                Thread.current['result']=[]
                main_thread['barrier']=false
                executor.hop
                hop_warn "GROUP THREAD end #{my_group} #{Thread.current}: #{Thread.current['result'].inspect}"
              end

              @threads[group]=t
              t.abort_on_exception=true
              while main_thread['barrier']
                sleep 0.1
              end
            end

#            hop_warn "PUT #{group} #{val.inspect}"
#-            @groups[group].synchronize do
#-              @threads[group]['input'] << val
#-            end
            pipes[group].put(val)
          end #while read source

          # process final section
          hop_warn "START GROUP final chain (#{@finalChain})"
          #hop_warn @groups.inspect
          pipes.each_pair do |name,pipe|
            hop_warn "GROUP thread finishing #{name}"
            pipe.put(nil)
#-            @groups[group].synchronize do
#-              @threads[group]['input'] << nil
#-              @threads[group]['input'] << nil
#-              @threads[group]['input'] << nil
#-            end
          end

          @threads.each_pair do |name,t|
            hop_warn "Try to join #{name} #{t} (#{t.status})"
            fin=t.join
            hop_warn "GROUP Thread #{t} joined (#{fin}/#{t.status})"
            #put result to output stream
            #a=[]
            a= t['result']
#            hop_warn "Result (#{name}): #{a.inspect}"
            a.each {|val|
              self.do_yield(val)
            }
#            hop_warn "Yielded"
          end
          hop_warn "GROUP FINISHED!\n-------------------------------"
          # write EOF to out stream
          self.do_yield(nil)
        rescue => e
          hop_warn "Exception in #{@stream_var} <- #{@source} (#{@mainChain}: #{e}. "+e.backtrace.join("\t\n")
        end
      end #~Thread
    end

    def do_yield(hash)
      # push data into out pipe

#      hop_warn "GROUP YIELD #{@name} to #{stream_var} #{hash.inspect}"
      varStore.setStream(@stream_var,hash)
    end

    # read next source line and write it into @source_var
    def readSource
      value=varStore.get(@local_stream)
#      hop_warn "GROUP READED from #{@local_stream} #{value.inspect}\n"

      varStore.set(@current_var, value)
#      group=@group_expr.eval(self)
#      hop_warn "#{@current_var}= #{@group_expr.inspect} = #{group.inspect}"
      return value
    end
  end

end
