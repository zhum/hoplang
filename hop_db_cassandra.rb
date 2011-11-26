require 'cassandra/0.8'

module Hopsa

  class CassandraHopstance < EachHopstance

    def initialize(parent, source)
      super(parent)
      cfg = Config['varmap'][source]
      address = cfg['address'] || 'localhost'
      port = cfg['port'] || '9160'
      @keyspace = cfg['keyspace']
      @column_family = cfg['cf'].to_sym
      @max_items = -1
      @max_items = cfg['max_items'].to_i if cfg['max_items']
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
      VarStor.set(self, @current_var, value)
    end

    private

    # gets short cassandra type string from full name
    def cassandra_type(s)
      s.split('.').last
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
      @enumerator = @cassandra.to_enum(:each, @column_family)
    end

    # converts long as string stored in Cassandra into Hoplang representation
    def to_long(s)
      Cassandra::Long.new(s).to_i.to_s
    end
  end
end

