require 'fastercsv'
#csv = FCSV

f=File.open('/etc/passwd','r')
c=CSV.new(f,:col_sep => ':')
c.each{|l|
  print l[2]
}
f.close
