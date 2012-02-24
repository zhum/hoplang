#!/usr/bin/ruby

require './hoplang.rb'
include Hopsa

#ex=TopStatement.new
raw_text = <<_PROGRAM
var abc
#  test
abc = 1
yield abc + 1, 10
out = each x in ttt where x.np > 97
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

# hangs if this is commented out when x.np > 97, but not for x.np > 98
# and greater values
# print out

#out2 = seq y in out
# var s, n
# s = s + y.d
# n = n + 1
#final
# yield sum => s, avg => s / n
#end

#out2 = each z in testbase
#  yield z.np, z.user
#end
# print out2

#include test_include.hpl

# compute total and average number of serdyuk's CPUs
# out3 = each t in tasks where t.user == 'andrew'
#  yield taskid => t.taskid, ncpus => t.ncpus
# end
# print out3

out5 = each v in cheb_cpu_user where v.node == 'node-44-03'
  yield time => v.time, node => v.node, cpu => v.value
end
print out5

# out6 = seq v in out5
# var s,n
# s = s + v.cpu
# n = n + 1
# final
# yield samples => n, avgcpu => s / n
# end
# print out6

_PROGRAM

text=raw_text.split "\n"
ex=load_program(text)
ex.hop
