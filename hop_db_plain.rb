require 'rubygems'

Infinity=1.0/0

class Range
  def intersection(other)
    raise ArgumentError, 'Not a Range' unless other.kind_of?(Range)

    my_min, my_max = first, exclude_end? ? max : last
    other_min, other_max = other.first, other.exclude_end? ? other.max : other.last

    new_min = self === other_min ? other_min : other === my_min ? my_min : nil
    new_max = self === other_max ? other_max : other === my_max ? my_max : nil

    new_min && new_max ? new_min..new_max : nil
  end

  alias_method :&, :intersection
end

module Hopsa

  class PlainDBConv

    def initialize(db_var)
      @db_var=db_var
      
      @eq=[]
      @gt=[]
      @lt=[]
    end

    def dv_var
      @db_var
    end

    def unary(ex,op)
      nil
    end

    def binary(ex1,ex2,op)

#      hop_warn "MONGO BINARY TODB: #{ex1}, #{ex2}, #{op}"
      case op
      when '+'
        return nil
      when '*'
        return nil
      when '/'
        return nil
      when '-'
        return nil
      when '=='
        if ex1 == @db_var
          @eq<<ex2
        elsif ex2 == @db_var
          @eq<<ex1
        else
          # not field name...
          return nil
        end
        return self
      when '>'
        if ex1 == @db_var
          return [ex2,Infinity]
        elsif ex2 == @db_var
          return [-Infinity,ex1]
        end
        return nil
      when '<'
        if ex1 == @db_var
          return [-Infinity,ex2]
        elsif ex2 == @db_var
          return [ex1,Infinity]
        end
        return nil
      when '&' # string catenation
        return nil
      end
      return nil
    end

    def or(ex1,ex2)
      ret=[]
      (ex1+ex2).each do |i1|
        ret2=[]
        ret.each do |i2|
          if i1 & i2
            ret2 << [i1.first,i2.first].min .. [i1.last,i2.last].max
          else
            ret2 << i1 << i2
          end
        end
        ret=ret2
      end
      return ret
    end

    def and(ex1,ex2)
      ret=[]
      ex1.each do |i1|
        ex2.each do |i2|
          r= i1 & i2
          ret << r unless r.nil?
        end
      end
      return ret
    end

    def value(ex)
      ret = ex.gsub(Regexp.new('\W'+@db_var+'\.'),'')
      return ret.to_s
    end
  end

  class PlainHopstance < EachHopstance

    # provides 'each' functionality for Database request with indices
    class IndexedIterator
      def initialize(db, cf, index_clause, where_clause, context)
        @db = db
        @collection = cf
        
        @fileds=...
        @file=get_file(cf)
        @index_clause = index_clause
        @where_clause = where_clause
        @context=context
      end

      def each
        begin
          Ccsv.foreach(@file) do |row|
#!inline            var=row2var(row)
            var={}
            @fields.each_with_index do |f,i|
              var[f]=row[i]
            end

            if @where_clause
#              hop_warn "WHERE=#{@where_clause.inspect}"
              if @where_clause.eval(@context)
                yield var
              end
            else
              yield var
            end
          end
        rescue => e
          hop_warn "MONGO_DB Exception: #{e.message}\n"+e.backtrace.join("\t\n")
        end
        raise StopIteration

      end # each
    end # IndexedIterator

    def initialize(parent, source, current_var, where)
      super(parent)
      cfg = Config['varmap'][source]
      @split_field=cfg['field']
      @root_dir=cfg['dir']
      @source=source

      @current_var = current_var
      @where_expr = HopExpr.parse(where)

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
      varStore.set(@current_var, val)
    end

    private

    def create_filter(filter)
      db_expr,hop_expr=filter.to_db(self,PlainDBConv.new(@current_var)
    end

    # lazy initialization, done on reading first element
    def lazy_init
      # build index clause if possible
      dummy,@where_clause = create_filter @where_expr
      ind_iter = IndexedIterator.new @root_dir, @split_field, @where_clause, self
      @enumerator = ind_iter.to_enum(:each)
    end # lazy_init
  end # MongoHopstance
end
