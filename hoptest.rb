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
# yield taskid => t.taskid, ncpus => t.ncpus
#end
#print out3

out5 = each v in cheb_cpu_user where v.node == 'node-02-02' and v.time > 1326744000000 and v.time < 1326754000000
 yield time => v.time, node => v.node, cpu => v.value
end
print out5

#out4 = seq t in out3 
# var ncpus, n
# ncpus = ncpus + t.ncpus
# n = n + 1
#final
# yield ntasks => n, avgncpus => ncpus / n
#end
#print out4

_PROGRAM

text=raw_text.split "\n"
ex=load_program(text)
ex.hop
