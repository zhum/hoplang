# coding: utf-8
require 'rubygems'
require 'bson'
require 'mongo'

module Hopsa

  class MongoDBConv
    #@@do_or_pushing=true

    def initialize(db_var,do_or_push=nil)
      @db_var=db_var
      #do_or_push = @@do_or_pushing if do_or_push.nil?
      #@do_or_pushing=do_or_push
    end

#    def do_or_pushing(flag=nil)
#      last=@@do_or_pushing
#      @@do_or_pushing=flag unless flag.nil?
#      last
#    end

    def db_var
      @db_var
    end

    def unary(ex,op)
#      return '! ('+ex.to_s+')' if (op == 'not') or (op == '!')
      return nil
    end

    OPS={'>' => '$gt', '<' => '$lt', '<=' => '$lte', '>=' => '$gte',
         '!=' => '$ne', '.<' => '$lt', '.>' => '$gt', '.<=' => '$lte', 
        '.>' => '$gte'}
    REV_OPS={'>' => '$lt', '<' => '$gt', '<=' => '$gte', '>=' => '$lte',
         '!=' => '$ne', '.<' => '$gt', '.>' => '$lt', '.<=' => '$gte', 
      '.>=' => '$lte'}

    def binary(ex1,ex2,op)

      hop_warn "MONGO BINARY TODB: #{op}, #{ex1}, #{ex2}"
      case op
      when '+'
        return nil #"#{ex1} + #{ex2}"
      when '-'
        return nil # "#{ex1} - #{ex2}"
      when '*'
        return nil # "#{ex1} * #{ex2}"
      when '/'
        return nil # "#{ex1} / #{ex2}"

      when /^==$/
        if ex1 =~ /^\w+$/
          # first argument = 'dbname.field'
          return {ex1 => ex2}
        elsif ex2 =~ /^\w+$/
          # second argument is... So swap 'em!
          return {ex2 => ex1}
        else
          # not field name...
          return nil
        end
      when /^\.?[<>]=?|!=$/
        if ex1 =~ /^\w+$/
          # first argument = 'dbname.field'
          left=ex1
          op2=OPS[op]
        elsif ex2 =~ /^\w+$/
          # second argument is... So swap 'em!
          left=ex2
          ex2=ex1
          op2=REV_OPS[op]
        else
          # not field name...
          return nil
        end

        #hop_warn "RET: (this.#{left} #{op2} #{ex2})"
        ex2=ex2.to_i unless op.start_with? '.'
        return {left => {op2 => ex2}}
      when '&' # string concatenation
        return nil

      #when 'ins' # nodeset membership
      #  return inset ex1, ex2

      end
      return nil
    end

    # nodeset conversion, ex1 is variable name, ex2 is nodeset
    def inset(ex1, ex2)
      return nil unless ex1 =~ /^\w+$/
      ranges = (NodeSet.by_str ex2).ranges
      and_exprs = ranges.map do |r|
        case r 
        when String
          {ex1 => r}
        when Range
          {ex1 => {'$gte' => r.min, '$lte' => r.max}}
        end
      end
      [and_exprs].flatten
    end

    def or(ex1,ex2)
      return [ex1,ex2].flatten
      return nil
    end

    def and(ex1,ex2)
      ret=[]
      begin
        [ex1].flatten.each { |e1|
          begin
            ret1=e1['$and'] || e1
          rescue
            ret1=e1
          end
          [ex2].flatten.each { |e2|
            begin
              ret2=e2['$and'] || e2
            rescue 
              ret2=e2
            end
            ret << {'$and' => [ret1,ret2].flatten}
          }
        }
      rescue
        ret=nil
      end
      return ret.flatten
    end

    def value(ex)
      ret = ex.gsub(Regexp.new('\W'+@db_var+'\.'),'')
      return ret.to_i if ret =~ /^[0-9]+$/
      ret.gsub! /^'|"/, ''
      ret.gsub! /'|"$/, ''
      return ret.to_s
    end

    def wrapper(ex)
      #ex.gsub!('"','\\"');
      hop_warn "WRAPPER: #{ex.inspect}."
      return ex
    end
  end

  class MongoDBDriver < HopsaDBDriver

    # parent hopstance, source var name, 'where' expression
    def initialize(parent, source, current_var, where)

      super(parent,source, current_var, where)

      cfg = Config['varmap'][source]
      address = cfg['address'] || 'localhost'
      port = cfg['port'] || nil
      database = cfg['database']

      @db = Mongo::Connection.new(address, port).db(database)
      @collection = cfg['collection'].to_sym
      if not cfg['user'].nil?
        if db.authenticate(cfg['user'], cfg['password'])
          hop_warn "Auth with MongoDB failed\n"
        end
      end
      @push_index = true
      @push_index = false if cfg['push_index'] && cfg['push_index'] == 'false'
      @enumerator = nil
      @context=HopContext.new(parent)
      @context.varStore.addScalar(current_var)
    end

    def readSource
      if @enumerator.nil?
        lazy_init
      end
      val = nil
      begin
        val = @enumerator.next
      rescue StopIteration
        hop_warn "finished iteration"
      end
      return val
    end

    private

    # checks whether filter can be pushed into DB, and returns an
    # object which can be passed to get_index_slices if it can be
    # a filter can be pushed into DB, if it is an AND of single-expression
    # conditions, each of which has the form of v.f op expr, where
    # v is the variable name declared in each (@current_var.name)
    # f is the name of the field of the variable, and that field is indexed (for
    # Cassandra)
    # op is one of <, <=, >, >=, ==
    # expr is an expression of simple form, currently must be a constant
    # currently, the order must be exact (i.e. v.f to the left only), in future
    # the requirement will be relaxed. Keys and column names will also be
    # supported in future
    #PUSH_OPS = ['<', '<=', '>', '>=', '==']
    def create_filter(filter)
      return nil,nil if filter.nil?

      db_adapter = MongoDBConv.new(@current_var, true) #do push 'or'

      db_expr,hop_expr = filter.db_conv(@parent, db_adapter) 
    end

    # lazy initialization, done on reading first element
    def lazy_init
      # build index clause if possible
      @index_clause,@where_clause = create_filter @where_expression
      hop_warn "INDEX: #{@index_clause.inspect}"
      if @index_clause and @push_index
        ind_iter = IndexedIterator.new(@db, @collection, @index_clause, @where_clause, @parent, @current_var)
        @enumerator = ind_iter.to_enum(:each)
        hop_warn "index pushed to Mongo #{@where_expression.to_s}"
      else
        ind_iter = IndexedIterator.new(@db, @collection, nil, @where_clause, @parent, @current_var)
        @enumerator = ind_iter.to_enum(:each)
        hop_warn 'index not pushed to Mongo' if @where_expression
      end
    end # lazy_init
  end # MongoHopstance


    # provides 'each' functionality for Database request with indices
    class IndexedIterator
      def initialize(db, cf, index_clause, where_clause, context_source, current_var)
        @db = db
        @collection = cf
        @index_clause = index_clause
        @where_clause = where_clause
        @context_source=context_source
        @current_var=current_var
      end

      def to_hash(h)
        ret={}
        h.each_pair{ |k,v|
          ret[k]=v.to_s unless k == '_id'
        }
        return ret
      end

      def each
        begin
          coll = @db[@collection]
          @context=HopContext.new(@context_source)
          @context.varStore.addScalar(@current_var)

#          iter = coll.find(@index_clause)
          hop_warn "SEARCH: #{@index_clause.inspect}"
          @context=HopContext.new(@context_source)
          @context.varStore.addScalar(@current_var)

          [@index_clause].flatten.each { |index|
            hop_warn "Search iteration=#{index.inspect}"
            coll.find(index).each { |row|
              if @where_clause
                @context.varStore.set(@current_var,row)
                result=@where_clause.eval(@context)
                #hop_warn "WHERE [#{result}] #{@where_clause.inspect} read: #{row.inspect} \nContext: #{@context.inspect}"
                if result
                  yield to_hash row
                end
              else
                yield to_hash row
              end
            }
          }
        rescue => e
          hop_warn "MONGO_DB Exception: #{e.message}\n"+e.backtrace.join("\t\n")
        end
        raise StopIteration

      end # each
    end # IndexedIterator

end
