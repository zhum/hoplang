require 'rubygems'
require 'set'
require 'ccsv'
gem 'ccsv', '>= 0.2.0'

#
# Range class extension for implementation of 'range logic'
#
class Range

  #
  # intersects one range with another
  #
  # :returns: intersected range or nil, if intersection is empty
  #
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

module Hopsa  # :nodoc:

  class PlainDBConv

    def initialize(db_var,split_f)
      @db_var=db_var
      @split_f=split_f
    end

    def db_var
      @db_var
    end

    def unary(ex,op)
      nil
    end

    def binary(ex1,ex2,op)
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
        if ex1 == @split_f
          return [ex2.to_f .. Float::MAX]
        elsif ex2 == @split_f
          return [-Float::MIN .. ex1.to_f]
        end
        return nil
      when '<'
        if ex1 == @split_f
          return [-Float::MIN .. ex2.to_f]
        elsif ex2 == @split_f
          return [ex1.to_f .. Float::MAX]
        end
        return nil
      when '&' # string catenation
        return nil
      end
      return nil
    end

    def or(ex1,ex2)
      return nil if @no_split
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
      return nil if @no_split
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

  #
  # CSV-tree driver for HOPLANG
  #
  # config *should* contain definitions of:
  #   [split]  fieldname, which defines splitting
  #   [dir]    path to files catalog
  #   [fields] list of fileds in right order (files are without headers!)
  #
  #
  class PlainDBDriver < EachHopstance

    # provides 'each' functionality 
    class IndexedIterator
      def initialize(root_dir, csv_ranges, fields, where_clause, context )
        @files=get_files(root_dir,csv_ranges)
        @where_clause = where_clause
        @context=context
        @fields=fields
      end

      #
      # get csv filenames for given list of ranges
      # 
      def get_files(root,ranges)
        selected=Set.new
        ret=[]

        files = Dir.entries(root).map{|f| /^(?<r>\d+)\.csv$/.match(f) ? $~[:r] : nil}.reject{|f| f.nil?}.sort

        return files.map {|f| File.join(root,"#{f}.csv")} if ranges.nil?

        ranges.each do |r|
          files.each_with_index do |f,i|
            if r.include? f.to_f
              selected << i
              selected << i-1 if i-1>=0
            end
          end
        end

        selected.each do |i|
          ret << File.join(root,"#{files[i]}.csv")
        end

        hop_warn "Files: #{ret.inspect}"
        ret.sort
      end

      def each
        begin
          @files.each do |file|
            hop_warn "DO FILE: #{file}"
            ::Ccsv.foreach(file) do |row|
#!inline            var=row2var(row)
              var={}
              @fields.each_with_index do |f,i|
                var[f]=row[i]
              end
              hop_warn "VAR=#{var.inspect}"

              if @where_clause
                hop_warn "WHERE=#{@where_clause.inspect}"
                if @where_clause.eval(@context)
                  yield var
                end
              else
               yield var
              end
            end
          end
        rescue => e
          hop_warn "PLAIN_CSV Exception: #{e.message}\n"+e.backtrace.join("\t\n")
        end
        raise StopIteration

      end # each
    end # IndexedIterator

    #
    # [parent]      parent hopstance
    # [source]      source stream name
    # [current_var] variable name
    # [where]       'where' expression
    #
    def initialize(parent, source, current_var, where)
      super(parent)

      hop_warn "------------------------------ #{current_var}"
      self.varStore.addScalar(current_var)

      cfg = Config['varmap'][source]
      @split_field=cfg['split']
      @root_dir=cfg['dir']
      @source=source
      @fields=cfg['fields']
      hop_warn "FF: #{@fields}"

      @current_var = current_var
      @where_expr = where.nil? ? nil : HopExpr.parse(where)

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
      db_expr,hop_expr=filter.to_db(self,PlainDBConv.new(@current_var,@split_field))
      hop_warn "Create_filter: #{db_expr.inspect} #{hop_expr.inspect}"
    end

    # lazy initialization, done on reading first element
    def lazy_init
      # build index clause if possible
      @csv_ranges,@where_clause = create_filter @where_expr
      hop_warn "RANGES: #{@csv_ranges.inspect}"
      ind_iter = IndexedIterator.new @root_dir, @csv_ranges, @fields, @where_clause, self
      @enumerator = ind_iter.to_enum(:each)
    end # lazy_init
  end # MongoHopstance
end
