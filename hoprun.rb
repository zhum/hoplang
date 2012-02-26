#!/usr/bin/ruby

require './hoplang.rb'
include Hopsa

#begin
file_found = nil
ARGV.each do |a|
  # miss arguments
  next if a =~  /([^=]+)=(.+)/
  file_found = true
  text=[]
  File.open(a).each do |line|
    text.push line
  end
  ex=load_program(text)
  ex.hop
end
unless file_found
  while $stdin.fgets
    text.push $_
  end
  ex=load_program(text)
  ex.hop
end
#rescue => e
#  hop_warn "Oooops! #{e.message}\n"+e.backtrace.join("\t\n");
#end
