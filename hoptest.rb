#!/usr/bin/ruby

require './hoplang.rb'
include Hopsa


#ex=TopStatement.new
raw_text = <<_PROGRAM
scalar abc
#  test
abc=1
yield abc 1 + , 10
out = each x in ttt
 scalar delta
 delta=x.end x.start -
 yield delta , x.user
final
 yield 55 , "petya"
end

out2 = each y in out
  yield y.field_1 1 + , y.field_2
end

out3 = each z in testsplit
  scalar temp
  temp = 20 10 +
  yield temp , z.user , z.np
end
_PROGRAM

text=raw_text.split "\n"
ex=load_program(text)
ex.hop

