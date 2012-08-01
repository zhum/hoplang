# nodesets, compact representation of the sets of nodes

# nodeset syntax (no spaces allowed in between):
# nodeset ::= nodeterm{,nodeterm}
# nodeterm ::= fpart [vpart] (vpart is optional)
# fpart is fixed part (fixed string), vpart is variable part (in brackets,
# number ranges separated by commas; all numbers in the brackets have the same
# number of digits)
# fpart ::= [-_:a-zA-Z0-9]*
# vpart ::= [numset{,numset}] (brackets are literal, not metacharacters)
# numset ::= single | range
# single ::= \d+
# range ::= single-single
# all numsets inside a single vpart have the same number of digits

require 'citrus'

module Hopsa

  Citrus.load 'hop_ns'

  # interface to node sets
  class NodeSet

    # checks membership of a single node in a set of nodes
    def self.inset(node_str, nodeset_str)
      (NodeSet.by_str nodeset_str).match node_str
    end

    # a hash which maps nodesets by strings
    @@node_sets = {}

    # gets a nodeset corresponding to a given string. If such a nodeset exists
    # already, it is returned, otherwise, a new one is created
    def self.by_str(nodeset_str)
      unless @@node_sets[nodeset_str]
        @@node_sets[nodeset_str] = NodeSet.new nodeset_str
      end
      @@node_sets[nodeset_str]
    end

    # parses a nodeset string into a root node
    def self.parse_ns_str(nodeset_str)
      (NodeSetGram.parse nodeset_str, :root => :nodeset).value
    end

    attr_reader :root

    # initialize a nodeset from a nodeset string
    def initialize(nodeset_str)
      @root = NodeSet.parse_ns_str nodeset_str
    end
    
    # string representation of a nodeset
    def to_s 
      @root.to_s
    end

    # regexp for a nodeset
    def regexp
      @regexp = (Regexp.compile @root.regexp) unless @regexp
      @regexp
    end

    # regexp string for a nodeset, for debugging use only
    def regexp_str
      @root.regexp
    end

    # matches a node against a nodeset
    def match(node_str)
      # TODO: match against a regexp
      @root.match node_str
    end

    # matches a node against a nodeset regexp
    def match_regexp(node_str)
      regexp.match node_str
    end

    # ranges/match values for the set of nodes
    def ranges
      @root.range_list.map do |r|
        if r.count == 1
          r[0]
        else
          r[0] .. r[1]
        end
      end
    end
  end # class NodeSet

  # nodeset is represented as a tree of nodes; nodes types are:
  # NodeSetNode - the base class
  # ChoiceSetNode - matches one of its subnodes; all subnodes must have the same
  # length; corresponds to ',' operator
  # BracketChoiceSetNode - bracketed choice set node; the only difference from
  # basic set node is that brackets are added when the node is converted back to
  # string 
  # CatSetNode - matches against a concatenation of submatches
  # FixedSetNode - matches against a fixed string
  # RangeSetNode - matches against a range, currently only of numbers,
  # corresponds to '-' operator; all numbers have the same value

  # each type of nodes supports the following methods:
  # match - matches the substring against a node, result is true/false
  # regexp - a regexp equivalent to the current node, may be used to quickly
  # match the node
  # to_s - a string equivalent of the nodeset, usually a string from which it
  # was parsed
  # length - the length which the set node matches; in choice operators, all
  # lengths for choice subnodes must be the same, so that the length is
  # well-defined
  # node_list - a list of nodes, such that comparing the test node against each
  # node in the list, and then OR-ing the result of comparison is the same as
  # matching against a nodeset; 
  # range_list - similar to node_list, but also allows lexicographic ranges
  # (both ends included); typically, in CatSetNode, range_list is called for the
  # last entry, while node_list is called against previous entries (the result
  # is then concatenated). Both node_list and range_list operate with arrays
  # containing 1 (for == comparison) or 2 (for ranges) nodes; the result is
  # converted to an array of strings and ranges by NodeSet

  # base class for nodeset nodes
  class NodeSetNode
    # length of the string portion to match
    attr_reader :length
    # start of the substring to match; for use by parent expression only
    attr_accessor :str_start
    def initialize(length) 
      @length = length
    end
    def match(node_str)
      throw Error
    end
    def regexp 
      throw Error
    end
    def to_s 
      throw Error
    end
    def length 
      @length
    end
    def node_list
      throw Error
    end
    def range_list
      throw Error
    end
  end # NodeSetNode
 
  # a fixed node, which matches against a fixed string
  class FixedSetNode < NodeSetNode
    attr_reader :str
    def initialize(str)
      super str.length
      @str = str
    end
    def match(node_str)
      node_str == @str
    end
    def regexp 
      @str
    end
    def to_s
      @str
    end
    def node_list
      [[@str]]
    end
    def range_list
      [[@str]]
    end
  end  # class FixedSetNode

  # a number range node, which matches against numbers inside a range
  class RangeSetNode < NodeSetNode
    attr_reader :start, :finish
    def initialize(start, finish)
      super start.length
      throw Error unless start.length == finish.length
      throw Error unless start =~ /^\d+$/ && finish =~ /^\d+$/
      throw Error unless start <= finish
      @start = start
      @finish = finish
      @start_num = @start.to_i
      @finish_num = @finish.to_i
    end
    def match(node_str)
      node_str.length == @length && node_str =~ /^\d+$/ && 
        node_str.to_i >= @start_num && node_str.to_i <= @finish_num
    end
    # 2-8 => [2-8]
    # 02-08 => 0[2-8]
    # 02-18 => 02-09,10-18 => 0[2-9]|1[0-8]
    # 02-38 => 02-09,10-29,30-38 => 0[2-9]|[12]\d|3[0-8]
    # 045-431 => 045-099,100-399,400-431 =>
    # 045-049,050-099,100-399,400-429,430-431 => 
    # 0(4[5-9]|[5-9]\d)|[1-3]\d\d|4([0-2]\d|3[01])
    def regexp
      strings_to_regexp @start, @finish
    end
    # converts two digit characters (dc1 <= dc2) to a matching regexp
    def digits_to_regexp(dc1, dc2)
      throw Error unless dc1 <= dc2
      if dc1 == dc2
        dc1
      elsif dc1 == '0' && dc2 == '9'
        "\\d"
      elsif dc1.to_i == dc2.to_i - 1
        "[#{dc1}#{dc2}]"
      else
        "[#{dc1}-#{dc2}]"
      end
    end
    # gets the next character
    def nextchr(c)
      c.next
    end
    # gets the previous character
    def prevchr(c)
      res = ' '
      res.setbyte 0, c.ord - 1
      res
    end
    # converts a range of two equal-length strings into a matching regexp
    def strings_to_regexp(ds1, ds2)
      len = ds1.length
      throw Error unless ds2.length == len
      return (digits_to_regexp ds1, ds2) if len == 1
      # check first characters of a string
      return "\\d" * len if strings_full ds1, ds2
      dc1, dc2 = ds1[0], ds2[0]
      tds1, tds2 = ds1[1..-1], ds2[1..-1]
      if strings_full tds1, tds2
        return "#{digits_to_regexp dc1, dc2}#{strings_to_regexp tds1, tds2}"
      elsif dc1 == dc2
        return "#{dc1}#{strings_to_regexp tds1,tds2}"
      elsif dc1.to_i == dc2.to_i - 1
        return "(#{dc1}#{strings_to_regexp tds1, '9'*(len-1)}" +
          "|#{dc2}#{strings_to_regexp '0'*(len-1), tds2})"
      else
        return "(#{dc1}#{strings_to_regexp tds1, '9'*(len-1)}" +
          "|#{digits_to_regexp (nextchr dc1), (prevchr dc2)}" + 
          "#{strings_to_regexp '0'*(len-1), '9'*(len-1)}" + 
          "|#{dc2}#{strings_to_regexp '0'*(len-1), tds2})"
      end
    end
    # checks whether ranges are full, i.e. 0..0 - 9..9
    def strings_full(ds1, ds2)
      ds1 =~ /^0+$/ && ds2 =~ /^9+$/
    end
    def node_list
      (@start .. @finish).to_a.map {|s| [s]}
    end
    def range_list
      [[@start, @finish]]
    end
    def to_s
      "#{@start}-#{@finish}"
    end
  end # class RangeSetNode

  # intermediate class for inner set nodes
  class InnerSetNode < NodeSetNode
    attr_reader :children
    def initialize(children,length)
      super length
      @children = children
    end
  end
  
  # a nodeset formed by concatenation of substrings
  class CatSetNode < InnerSetNode
    # start of the string portion to match against a child
    def initialize(children)
      super children, children.map{|n| n.length}.reduce(:+)
      str_start = 0
      @children.each do |n|
        n.str_start = str_start
        str_start += n.length
      end
    end
    def match(node_str)
      return false unless node_str.length == @length
      @children.map{|n| n.match node_str[n.str_start, n.length]}.reduce(:&)
    end
    def regexp
      @children.map{|n| n.regexp}.reduce(:+)
    end
    def to_s
      @children.map{|n| n.to_s}.reduce(:+)
    end
    def node_list
      list = []
      new_list = []
      @children.each do |n|
        nlist = n.node_list
        new_list = []
        if list.count > 0
          list.each do |e1|
            new_list += nlist.map { |e2| [e1[0] + e2[0]] }
          end
        else
          new_list = nlist
        end
        list = new_list
      end
      return list
    end
    def range_list
      list = []
      new_list = []
      @children.reverse_each do |n|
        if list.count > 0
          # non-last element, just nodelist
          nlist = n.node_list
          new_list = []
          nlist.each do |e1|
            new_list += list.map { |e2| e2.map {|e3| e1[0] + e3} }
          end
        else 
          # last element, get ranges
          new_list = n.range_list
        end
        list = new_list
      end
      return list
    end
  end # class CatSetNode

  # a node at which choice is performed
  class ChoiceSetNode < InnerSetNode
    def initialize(children) 
      super children, children[0].length
      throw Error unless children.map{|n| n.length == @length}.reduce(:&)
    end
    def match(node_str)
      children.map {|n| n.match node_str}.reduce(:|)
    end
    def regexp
      crs = children.map{|n| n.regexp}
      if crs.length == 1
        crs[0]
      else
        "(" + (crs.join "|") + ")"
      end
    end
    def to_s
      children.map{|n| n.to_s}.join ","
    end
    def node_list
      children.map{|n| n.node_list}.reduce :concat      
    end
    def range_list
      children.map{|n| n.range_list}.reduce :concat      
    end
  end

  # a choice node which is bracketed
  class BracketedSetNode < ChoiceSetNode 
    def to_s
      '[' + super.to_s + ']'
    end
  end
  
end # module Hopsa
