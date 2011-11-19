#!/usr/bin/ruby

require './hoplang.rb'
include Hopsa



#ex=TopStatement.new
raw_text = <<_PROGRAM
scalar abc
#  test
abc = 1
yield abc + 1, 10
out = each x in ttt where x.np > 15
 scalar delta
 delta = x.end - x.start * 1 + 0
 scalar i
 i = 0
 while i < 3
  yield d => delta, x.user
  i = i + 1
 end
final
 yield d => 55, "petya"
end

out2 = each y in out
  yield d => y.d, y.field_2
end

#out2 = each z in testbase
#  yield z.np, z.user
#end

#include test_include.hpl

#out3 = each t in tasks
#  yield 'task ' & t.key & ' from ' & t.user
#end
_PROGRAM

text=raw_text.split "\n"
ex=load_program(text)
ex.hop
