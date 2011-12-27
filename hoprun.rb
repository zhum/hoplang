#!/usr/bin/ruby

require './hoplang.rb'
include Hopsa

if ARGV.size>0 then
  ARGV.each do|a|
    text=[]
    File.open(a).each do |line|
      text.push line
    end
    ex=load_program(text)
    ex.hop
  end
else
  while $stdin.fgets
    text.push $_
  end
  ex=load_program(text)
  ex.hop
end

