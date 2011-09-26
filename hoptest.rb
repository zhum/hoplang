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
_PROGRAM

text=raw_text.split "\n"
ex=load_program(text)
ex.hop

