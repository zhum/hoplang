#!/usr/bin/ruby

require './hoplang.rb'
include Hopsa



#ex=TopStatement.new
raw_text = <<_PROGRAM
scalar abc
#  test
abc = 1
yield abc + 1, 10
out = each x in ttt
 scalar delta
# must somehow become ints
 delta = x.end + x.start
 yield d => delta, x.user
final
 yield d => 55, 'petya'
end

out2 = each y in out
  yield d => y.d, y.field_2
end

#out2 = each z in testbase
#  yield z.np, z.user
#end

#include test_include.hpl

#out3 = each t in tasks
#  yield 'task ' + t.key + ' from ' + t.user
#end
_PROGRAM

text=raw_text.split "\n"
ex=load_program(text)
ex.hop
