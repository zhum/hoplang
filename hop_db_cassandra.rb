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
        @enumerator = @cassandra.to_enum(:each, @column_family)
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
        value = nil if @max_items != -1 && @items_read > @max_items
      end
      VarStor.set(self, @current_var, value)
    end
  end
end

