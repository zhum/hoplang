#!/usr/bin/ruby

require './hoplang.rb'
include Hopsa

#ex=TopStatement.new
raw_text = <<_PROGRAM
var abc
#  test
abc = 1
yield abc + 1, 10
out = each x in ttt where x.np > 15
 var delta
 delta = x.end - x.start * 1 + 0
 var i
 i = 0
 while i < 2
  if i == 0
    yield d => delta, u => x.user, i => i
  else
    yield d => delta, u => x.user, i => i + 1 
  end
  i = i + 1
 end
end

out2 = seq y in out
 var s, n
 s = s + y.d
 n = n + 1
final
 yield sum => s, avg => s / n
end

out2 = each z in testbase
  yield z.np, z.user
end

#include test_include.hpl

# compute total and average number of serdyuk's CPUs
#out3 = each t in tasks where t.user == 'serdyuk'
# yield key => t.key, ncpus => t.ncpus
#end

#out4 = seq t in out3 
# var ncpus, n
# ncpus = ncpus + t.ncpus
# n = n + 1
#final
# yield ncpus, n, ncpus / n
#end

_PROGRAM

text=raw_text.split "\n"
ex=load_program(text)
ex.hop
