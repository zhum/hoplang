require 'cassandra/0.8'

module Hopsa

  class CassandraHopstance < EachHopstance

    # provides 'each' functionality for Cassandra request with indices
    class IndexedIterator
      def initialize(cassandra, cf, index_clause, opts)
        @cassandra = cassandra
        @cf = cf
        @index_clause = index_clause
        # hope there will be no more rows than this number
        @opts = opts || {}
        opts[:key_count] = 1_000_000
      end
      def each
        @rows_read = 0
        @pre_rows = @cassandra.get_indexed_slices @cf, @index_clause, @opts
        @pre_rows.each do |k, vs|
          row = {}
          vs.each do |cosc|
            row[cosc.column.name] = cosc.column.value
          end
          yield k,row
        end # @pre_rows.each
        # raise StopIteration
      end # each
    end # IndexedIterator

    def initialize(parent, source)
      super(parent)
      cfg = Config['varmap'][source]
      address = cfg['address'] || 'localhost'
      port = cfg['port'] || '9160'
      @keyspace = cfg['keyspace']
      @keyname = cfg['keyname'] || 'key'
      # column name, has effect only for 2d driver
      @colname = cfg['colname'] || 'col'
      @valuename = cfg['valuename'] || 'value'
      @column_family = cfg['cf'].to_sym
      @max_items = -1
      @max_items = cfg['max_items'].to_i if cfg['max_items']
      @push_index = true 
      @push_index = false if cfg['push_index'] && cfg['push_index'] == 'false'
      @items_read = 0
      conn_addr = "#{address}:#{port}"      
      @cassandra = Cassandra.new @keyspace, conn_addr
      @enumerator = nil
    end

    def readSource
      if @enumerator.nil?
        lazy_init
      end
      kv = nil
      value = nil
      begin
        kv = @enumerator.next
        @items_read += 1
      rescue StopIteration
      end
      if !kv.nil?
        k,v=kv[0],kv[1]
        value = {@keyname => k}.merge(v)
        @columns_to_long.each do |column_name|
          value[column_name] = to_long value[column_name]
        end
        value = nil if @max_items != -1 && @items_read > @max_items
      end
      #puts value.inspect
      varStore.set(@current_var, value)
    end

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
    # the requirement will be relaxed.
    # the return tuple is of the form:
    # key_start, key_finish, col_start, col_end, filter_expr
    # any of the components may be null if it is absent; currently, col_start
    # and col_finish are both null. 
    PUSH_OPS = ['<', '<=', '>', '>=', '<.', '>.', '<=.', '>=.', '==']
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
      if !(check_binary filter)
        return nil,nil,nil,nil,nil
      end
      cfinfo = @cassandra.column_families[@column_family.to_s]
      # check leaves and build index clause
      index_clause = []
      key_start = nil
      key_end = nil
      col_start = nil
      col_end = nil
      has_eq = false
      push_index = true
      hop_warn @filter_leaves.inspect
      key_type = cassandra_type cfinfo.key_validation_class
      # has effect only for list of columns
      col_type = cassandra_type cfinfo.comparator_type
      @filter_leaves.each do |e|
        # remove trailing . for string comparison ops
        eop = e.op.sub /\./, ''
        if !(PUSH_OPS.include? e.op)
          push_index = false
          hop_warn "#{e.op} is not an index-pushable comparison"
          next
        end
        if !(e.expr1.instance_of? DotExpr)
          push_index = false
          hop_warn "first comparison operand is not a member access"
          next
        end
        if !(e.expr1.obj.instance_of? RefExpr) || e.expr1.obj.rname != @current_var
          push_index = false
          hop_warn "variable being accessed is not iteratable variable"
          next
        end
        if !(e.expr2.instance_of? ValExpr)
          push_index = false
          hop_warn "second comparison operand is not a value expression"
          next
        end
        # check if key, list of columns (2d) or column
        if e.expr1.field_name == @keyname
          if eop == '<' || eop == '<='
            key_end = to_cassandra_val(e.expr2.val, key_type)
          elsif eop == '>' || eop == '>='
            key_start = to_cassandra_val(e.expr2.val, key_type)
          elsif eop == '=='
            key_start = to_cassandra_val(e.expr2.val, key_type)
            key_end = to_cassandra_val(e.expr2.val, key_type)
          end
        elsif e.expr1.field_name == @colname
          if eop == '<' || eop == '<='
            col_end = to_cassandra_val(e.expr2.val, col_type)
          elsif eop == '>' || eop == '>='
            col_start = to_cassandra_val(e.expr2.val, col_type)
          elsif eop == '=='
            col_start = to_cassandra_val(e.expr2.val, col_type)
            col_end = to_cassandra_val(e.expr2.val, col_type)
          end
        else
          column_index = cfinfo.column_metadata.index do |col| 
            col.name == e.expr1.field_name
          end
          if !column_index
            push_index = false
            hop_warn "column #{e.expr1.field_name} not found in database"
            next
          end
          column = cfinfo.column_metadata[column_index]
          if !column.index_type
            push_index = false
            hop_warn "column #{e.expr1.field_name} is not indexed"
            next
          end
          index_clause += 
            [{
               :column_name => column.name, 
               :comparison => eop, 
               :value => to_cassandra_val(
                  e.expr2.val, cassandra_type(column.validation_class))
             }]
          has_eq = true if eop == '=='
        end # key / column
      end # @filter_leaves.each
      # check for eq in indices
      if !has_eq
        hop_warn "no == operator in filter expression"
        push_index = false
      end
      index_clause = nil if !push_index
      return key_start,key_end,col_start,col_end,index_clause
    end

    # gets short cassandra type string from full name
    def cassandra_type(s)
      s.split('.').last
    end

    # converts hoplang value to cassandra value for specific column type
    def to_cassandra_val(hv, cass_type)
      hv if !cass_type
      if cass_type == 'LongType'
        Cassandra::Long.new(hv.to_i).to_s
      else
        hv
      end
    end

    # lazy initialization, done on reading first element
    def lazy_init
      # keys and columns which need conversion to long
      cfinfo = @cassandra.column_families[@column_family.to_s]
      hop_warn "CAS: #{@column_family.to_s} / #{cfinfo}"
      @columns_to_long = []
      if cassandra_type(cfinfo.key_validation_class) == 'LongType'
        @columns_to_long += [@keyname]
      end
      if cassandra_type(cfinfo.comparator_type) == 'LongType'
        @columns_to_long += [@colname]
      end
      if cassandra_type(cfinfo.default_validation_class) == 'LongType'
        @columns_to_long += [@valuename]
      end
      cfinfo.column_metadata.each do |column_info|
        if cassandra_type(column_info.validation_class) == 'LongType'
          @columns_to_long += [column_info.name]
        end
      end
      # build index clause if possible
      key_start,key_end,col_start,col_end,@index_clause = 
        filter_exprs?(@where_expr)
      opts = {}
      if @index_clause && @push_index
        opts[:key_start] = key_start if key_start
        ind_iter = 
          IndexedIterator.new @cassandra, @column_family, @index_clause, opts
        @enumerator = ind_iter.to_enum :each
        hop_warn 'index filter pushed to Cassandra'
      else
        opts[:start_key] = key_start if key_start
        opts[:finish_key] = key_end if key_end
        opts[:start] = col_start if col_start
        opts[:finish] = col_end if col_end
        @enumerator = @cassandra.to_enum :each, @column_family, opts
        if @where_expr
          if key_start || key_end || col_start || col_end
            if key_start || key_end
              hop_warn 'key filter pushed to Cassandra'
            end
            if col_start || col_end
              hop_warn 'column filter pushed to Cassandra'
            end
          else
            hop_warn 'filter not pushed to Cassandra'
          end
        end
      end
    end

    # converts long as string stored in Cassandra into Hoplang string
    def to_long(s)
      Cassandra::Long.new(s).to_i.to_s
    end

  end # class Cassandra
end # module Hopsa
