require 'rubygems'
#require 'bson'
require 'mongo'

module Hopsa

  class MongoHopstance < EachHopstance

    # provides 'each' functionality for Database request with indices
    class IndexedIterator
      def initialize(db, cf, index_clause)
        @db = db
        @collection = cf
        @index_clause = index_clause
      end

      def each
        begin
          coll = @db[@collection]

          iter = coll.find(@index_clause)

          iter.each do |row|
            yield row
          end
        rescue => e
          hop_warn "MONGO_DB Exception: #{e.message}"
        end
        raise StopIteration

      end # each
    end # IndexedIterator

    def initialize(parent, source)
      super(parent)
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
#      if not val.nil?
#        k,v=kv[0],kv[1]
#        value = {'key' => k}.merge(v)
#        value = nil if @max_items != -1 && @items_read > @max_items
#      end
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
    PUSH_OPS = ['<', '<=', '>', '>=', '==']
    def filter_exprs?(filter)
      return nil if !filter
      @filter_leaves = []
      # check binary and collect leaves
      def check_binary(e)
        return nil if !(e.instance_of? BinaryExpr)
        if e.op == 'and'
          check_binary(e.expr1) && check_binary(e.expr2)
        elsif PUSH_OPS.include? e.op
          @filter_leaves += [e]
          true
        else
          nil
        end
      end
      return nil if !(check_binary filter)
      cfinfo = @db.collection_names
      col_index=nil
      # check leaves and build index clause
      index_clause = []
      has_eq = nil
      hop_warn @filter_leaves.inspect
      @filter_leaves.each do |e|
        return nil if !(PUSH_OPS.include? e.op)
        return nil if !(e.expr1.instance_of? DotExpr)
        return nil if !(e.expr1.obj.instance_of? RefExpr)
        return nil if e.expr1.obj.rname != @current_var
        return nil if !(e.expr2.instance_of? ValExpr)
        coll_index = cfinfo.index do |coll|
          coll == e.expr1.field_name
        end
        return nil if !col_index
        column = cfinfo[col_index]
        index_clause += [{:column_name => column.name, :comparison => e.op,
                           :value => e.expr2.val}]
        has_eq = true if e.op == '=='
      end
      if !has_eq
        hop_warn "no == operator in filter expression"
        return nil
      end
      index_clause
    end

    # lazy initialization, done on reading first element
    def lazy_init
      # build index clause if possible
      @index_clause = filter_exprs? @where_expr
      if @index_clause && @push_index
        ind_iter = IndexedIterator.new @db, @collection, @index_clause
        @enumerator = ind_iter.to_enum(:each)
        hop_warn 'index pushed to Mongo'
      else
        ind_iter = IndexedIterator.new @db, @collection, nil
        @enumerator = ind_iter.to_enum(:each)
        hop_warn 'index not pushed to Mongo' if @where_expr
      end
    end
  end
end
