require 'rubygems'
#require 'bson'
require 'mongo'

module Hopsa

  class MongoDBConv

    def initialize(db_var)
      @db_var=db_var
    end

    def unary(ex,op)
      #return '(not '+ex.to_s+')' if (op == 'not') or (op == '!')
      return nil
    end

    def binary(ex1,ex2,op)
      return nil if ex1.nil? or ex2.nil?

      warn "MONGO BINARY: #{ex1}, #{ex2}, #{op}"
      case op
      when '+'
        return nil
      when '*'
        return nil
      when '/'
        return nil
      when '-'
        return nil
      when '>'
        return ex1.to_s => {'$gt' => ex2.to_s}
      when '>='
        return ex1.to_s => {'$ge' => ex2.to_s}
      when '<'
        return ex1.to_s => {'$lt' => ex2.to_s}
      when '<='
        return ex1.to_s => {'$le' => ex2.to_s}
      when '=='
        return ex1.to_s => {'$eq' => ex2.to_s}
      when '!='
        return ex1.to_s => {'$ne' => ex2.to_s}
      end
      return nil
    end

    def value(ex)
      return ex.gsub(Regexp.new('\W'+@db_var+'\.'),'')
    end
  end

  class MongoHopstance < EachHopstance

    # provides 'each' functionality for Database request with indices
    class IndexedIterator
      def initialize(db, cf, index_clause, where_clause, context)
        @db = db
        @collection = cf
        @index_clause = index_clause
        @where_clause = where_clause
        @context=context
      end

      def each
        coll = @db[@collection]

        iter = coll.find(@index_clause)
        warn "SEARCH: #{@index_clause.inspect}"
        iter.each do |row|
          if @where_clause
            if @where_clause.eval(@context)
              yield row
            end
          else
            yield row
          end
        end
        raise StopIteration

      end # each
    end # IndexedIterator

    def initialize(parent, source, current_var, where)
      super(parent)
      cfg = Config['varmap'][source]
      address = cfg['address'] || 'localhost'
      port = cfg['port'] || nil
      database = cfg['database']

      @db = Mongo::Connection.new(address, port).db(database)
      @collection = cfg['collection'].to_sym
      @current_var = current_var
      @where_expr = HopExpr.parse(where)

      if not cfg['user'].nil?
        if db.authenticate(cfg['user'], cfg['password'])
          warn "Auth with MongoDB failed"
        end
      end
      @push_index = true
      @push_index = false if cfg['push_index'] && cfg['push_index'] == 'false'
      @enumerator = nil
    end

    def readSource
      if @enumerator.nil?
        lazy_init
      end
      val = nil
      begin
        val = @enumerator.next
      rescue StopIteration
        warn "finished iteration"
      end
      varStore.set(@current_var, val)
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
      cfinfo = @db.collection_names

      db_conv=MongoDBConv.new(@current_var)

      db_expr,hop_expr=filter.to_db(self,db_conv)
    end

    # lazy initialization, done on reading first element
    def lazy_init
      # build index clause if possible
      @index_clause,@where_clause = create_filter @where_expr
      if @index_clause and @push_index
        ind_iter = IndexedIterator.new @db, @collection, @index_clause, @where_clause ,self
        @enumerator = ind_iter.to_enum(:each)
        warn "index pushed to Mongo #{@where_expr.to_s}"
      else
        ind_iter = IndexedIterator.new @db, @collection, nil
        @enumerator = ind_iter.to_enum(:each)
        warn 'index not pushed to Mongo' if @where_expr
      end
    end # lazy_init
  end # MongoHopstance
end
