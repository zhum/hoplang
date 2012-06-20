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

# BAD tests - internal testing. replace by IndexedIterator tests
describe 'CSV driver' do
  it 'should load two csv in, belongs to range 100..250' do
    ranges=[Range.new(100,200), Range.new(150,250)]
    #h=Hopsa::PlainHopstance.new('.', ranges,'f',nil,nil)

    files=Hopsa::PlainDBDriver::IndexedIterator.get_files(ROOT,ranges)
    files.should == ["#{ROOT}/100.csv","#{ROOT}/200.csv"]
  end

  it 'should load no files if ranges not cover them' do
    ranges=[Range.new(400,500), Range.new(500,1500)]
    files=Hopsa::PlainDBDriver::IndexedIterator.get_files(ROOT,ranges)
    files.should == []
  end


end
