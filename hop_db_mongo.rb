# coding: utf-8
require 'rubygems'
require 'bson'
require 'mongo'

module Hopsa

  class MongoDBConv
    @@do_or_pushing=true

    def initialize(db_var,do_or_push=nil)
      @db_var=db_var
      do_or_push ||=@@do_or_pushing
      @do_or_pushing=do_or_push
    end

    def do_or_pushing(flag=nil)
      last=@@do_or_pushing
      @@do_or_pushing=flag unless flag.nil?
      last
    end

    def dv_var
      @db_var
    end

    def unary(ex,op)
#      return '! ('+ex.to_s+')' if (op == 'not') or (op == '!')
      return nil
    end

    OPS={'>' => '$gt', '<' => '$lt', '<=' => '$lte', '>=' => '$gte',
         '!=' => '$ne'}
    REV_OPS={'>' => '$lt', '<' => '$gt', '<=' => '$gte', '>=' => '$lte',
         '!=' => '$ne'}

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
      when /^<|>|(>=)|(<=)|(!=)$/
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
        return {left => {op2 => ex2}}
      when '&' # string catenation
        return nil

      end
      return nil
    end

    def or(ex1,ex2)
      return {'$or' => [ex1,ex2]} if @do_or_pushing
      return nil
    end

    def and(ex1,ex2)
      return {'$and' => [ex1,ex2]}
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

      db_adapter=MongoDBConv.new(@current_var,false) #do not push 'or'
      db_expr,hop_expr=filter.db_conv(self,db_adapter)
    end

    # lazy initialization, done on reading first element
    def lazy_init
      # build index clause if possible
      @index_clause,@where_clause = create_filter @where_expression
      hop_warn "INDEX: #{@index_clause.inspect}"
      if @index_clause and @push_index
        ind_iter = IndexedIterator.new @db, @collection, @index_clause, @where_clause ,self
        @enumerator = ind_iter.to_enum(:each)
        hop_warn "index pushed to Mongo #{@where_expression.to_s}"
      else
        ind_iter = IndexedIterator.new @db, @collection, nil, @where_clause ,self
        @enumerator = ind_iter.to_enum(:each)
        hop_warn 'index not pushed to Mongo' if @where_expression
      end
    end # lazy_init
  end # MongoHopstance


    # provides 'each' functionality for Database request with indices
    class IndexedIterator
      def initialize(db, cf, index_clause, where_clause, context)
        @db = db
        @collection = cf
        @index_clause = index_clause
        @where_clause = where_clause
        @context=context
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

#          iter = coll.find(@index_clause)
          hop_warn "SEARCH: #{@index_clause}"
          coll.find(@index_clause).each { |row|
            if @where_clause
              hop_warn "WHERE=#{@where_clause.inspect}"
              if @where_clause.eval(@context)
                yield to_hash row
              end
            else
              yield to_hash row
            end
          }
        rescue => e
          hop_warn "MONGO_DB Exception: #{e.message}\n"+e.backtrace.join("\t\n")
        end
        raise StopIteration

      end # each
    end # IndexedIterator

end
