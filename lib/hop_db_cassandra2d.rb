# coding: utf-8
# require 'cassandra/0.8'

module Hopsa

  # a class which handles 2D cassandra tables, and returns data as a list of
  # tuples of the form (keyname, colname, value)
  class Cassandra2dDBDriver < CassandraHopstance
    def readSource
      if @enumerator.nil?
        lazy_init
      end

      # get key-value pair
      begin
        if !@kv
          @kv = @enumerator.next
          #puts @kv[1].inspect
          @kvenum = @kv[1].to_enum :each
        end
      rescue StopIteration
      end

      # @kv == nil - finished iteration
      value = nil
      if @kv
        begin
          colv, valv = @kvenum.next
          @items_read += 1
          value = {@keyname => @kv[0], @colname => colv, @valuename => valv}
          @columns_to_long.each do |column_name|
            value[column_name] = to_long value[column_name]
          end
        rescue StopIteration
          begin
            @kvenum = nil
            @kv = @enumerator.next
            @kvenum = @kv[1].to_enum :each
            retry
          rescue StopIteration
          end
        end
      end
      value['__hoplang_cols_order'] = @hoplang_cols_order unless value.nil?
      value = nil if @max_items != -1 && @items_read > @max_items
      hop_warn 'finished cassandra2d iteration' if !value
      return value
    end # readSource

    # makes column order
    def make_cols_order
      heads = [@keyname, @colname, @valname]
      heads.join ', '
    end
  end # Cassandra2dHopstance

end # module Hopsa
