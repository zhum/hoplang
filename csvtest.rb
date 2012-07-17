#require 'fastercsv'
#csv = FCSV
require 'ccsv'

#f=File.open('/etc/passwd','r')
#c=CSV.new(f,:col_sep => ':')
Ccsv.foreach('/etc/passwd',':') {|l|
  puts l.inspect
}
#f.close
