#!!require 'cassandra/0.8'

module Hopsa

  class CassandraHopstance < EachHopstance

    # provides 'each' functionality for Cassandra request with indices
    class IndexedIterator
      def initialize(cassandra, cf, index_clause)
        @cassandra = cassandra
        @cf = cf
        @index_clause = index_clause
        # hope there will be no more rows than this number
        @key_count = 100_000_000
        @key_start = nil
      end
      def each
#        while true
          # get more rows if needed
          @rows_read = 0
          opts = {:key_count => @key_count}
          #opts[:key_start] = @key_start if @key_start
          @pre_rows = @cassandra.get_indexed_slices @cf, @index_clause, opts
          # @nrows_read = @pre_rows.count
          # puts "#{@nrows_read} row(s) read"
          # raise StopIteration if @nrows_read == 0 || (@nrows_read == 1 && @key_start)
          # iterate over rows, save the last as the start for the next batch
          irow = 0
          # @key_start = @pre_rows.keys.max
          @pre_rows.each do |k, vs|
            #if irow == @nrows_read - 1 && @nrows_read == @key_count
            #  puts k
            #  @key_start = k
            #  break # each
            #end
            # row to be yielded
            # additional conversion needed due to awful interface
            row = {}
            vs.each do |cosc|
              row[cosc.column.name] = cosc.column.value
            end
            yield k,row
            irow += 1
          end # @pre_rows.each
#        end # while
        raise StopIteration
      end # each
    end # IndexedIterator

    def initialize(parent, source)
      super(parent)
      cfg = Config['varmap'][source]
      address = cfg['address'] || 'localhost'
      port = cfg['port'] || '9160'
      @keyspace = cfg['keyspace']
      @column_family = cfg['cf'].to_sym
      @max_items = -1
      @max_items = cfg['max_items'].to_i if cfg['max_items']
      @push_index = true 
      @push_index = false if cfg['push_index'] && cfg['push_index'] == 'false'
      @items_read = 0
      conn_addr = "#{address}:#{port}"
 #!!     @cassandra = Cassandra.new @keyspace, conn_addr
      @enumerator = nil
    end

    def readSource
      if @enumerator.nil?
        lazy_init
      end
      kv = nil
      begin
        kv = @enumerator.next
        @items_read += 1
      rescue StopIteration
        puts "finished iteration"
      end
      if !kv.nil?
        k,v=kv[0],kv[1]
        value = {'key' => k}.merge(v)
        @columns_to_long.each do |column_name|
          value[column_name] = to_long value[column_name]
        end
        value = nil if @max_items != -1 && @items_read > @max_items
      end
      varStore.set(@current_var, value)
    end

    private

    # checks whether filter can be pushed into DB (Cassandra), and returns an
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
      cfinfo = @cassandra.column_families[@column_family.to_s]
      # check leaves and build index clause
      index_clause = []
      has_eq = nil
      puts @filter_leaves.inspect
      @filter_leaves.each do |e|
        return nil if !(PUSH_OPS.include? e.op)
        return nil if !(e.expr1.instance_of? DotExpr)
        return nil if !(e.expr1.obj.instance_of? RefExpr)
        return nil if e.expr1.obj.rname != @current_var
        return nil if !(e.expr2.instance_of? ValExpr)
        column_index = cfinfo.column_metadata.index do |col| 
          col.name == e.expr1.field_name
        end
        return nil if !column_index
        column = cfinfo.column_metadata[column_index]
        return nil if !column.index_type
        index_clause += [{:column_name => column.name, :comparison => e.op, 
                           :value => to_cassandra_val(e.expr2.val, column)}]
        has_eq = true if e.op == '=='
      end
      if !has_eq
        warn "no == operator in filter expression"
        return nil
      end
      index_clause
    end

    # gets short cassandra type string from full name
    def cassandra_type(s)
      s.split('.').last
    end

    # converts hoplang value to cassandra value for specific column type
    def to_cassandra_val(hv, col)
      hv if !col
      if cassandra_type(col.validation_class) == 'LongType'
        Cassandra::Long.new(hv.to_i).to_s
      else
        hv
      end
    end

    # lazy initialization, done on reading first element
    def lazy_init
      # keys and columns which need conversion to long
      cfinfo = @cassandra.column_families[@column_family.to_s]
      @columns_to_long = []
      if cassandra_type(cfinfo.comparator_type) == 'LongType'
        @columns_to_long += ['key']
      end
      cfinfo.column_metadata.each do |column_info|
        if cassandra_type(column_info.validation_class) == 'LongType'
          @columns_to_long += [column_info.name]
        end
      end
      # build index clause if possible
      @index_clause = filter_exprs? @where_expr
      if @index_clause && @push_index
        ind_iter = IndexedIterator.new @cassandra, @column_family, @index_clause
        @enumerator = ind_iter.to_enum(:each)
        warn 'index pushed to Cassandra'
      else
        @enumerator = @cassandra.to_enum(:each, @column_family)
        warn 'index not pushed to Cassandra' if @where_expr
      end
    end

    # converts long as string stored in Cassandra into Hoplang string
    def to_long(s)
      Cassandra::Long.new(s).to_i.to_s
    end
  end
end
