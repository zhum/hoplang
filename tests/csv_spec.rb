require 'rspec'
require './hoplang.rb'

include Hopsa

ROOT='./tests'

describe 'Ranges extension' do
  it 'should intersect two ranges' do
    r1=Range.new(100,200)
    r2=Range.new(150,250)
    (r1&r2).should == Range.new(150,200)
  end
end

describe 'CSV driver' do
  it 'should load two csv in, belongs to range 100..250' do
    ranges=[Range.new(100,200), Range.new(150,250)]
    #h=Hopsa::PlainHopstance.new('.', ranges,'f',nil,nil)

    files=Hopsa::PlainHopstance::IndexedIterator.get_files(ROOT,ranges)
    files.should == ["#{ROOT}/100.csv","#{ROOT}/200.csv"]
  end
end
