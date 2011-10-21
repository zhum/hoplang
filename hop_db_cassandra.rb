#require 'cassandra/0.8'

module Hopsa

  class CassandraHopstance < EachHopstance

    def init(text,pos,streamvar,current_var,source,where)
      @address = '127.0.0.1:9160'
      @keyspace = 'hopsa'
      @column_family = :tasks_cheb
      @next_key = nil
      @end_of_stream = false
      # for test purposes only
      @max_items = 100
      @items_read = 0

      newStartLine = super(text,pos,streamvar,current_var,source,where)
      @cassandra = Cassandra.new('hopsa', 'localhost:9160')
      @enumerator = nil
      newStartLine
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
        value = nil if @items_read > @max_items
      end
      VarStor.set(self, @current_var, value)
    end
  end
end

