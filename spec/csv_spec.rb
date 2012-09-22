require 'rspec'
require 'hoplang'

include Hopsa

ROOT='tests/db'

describe 'Ranges extension' do
  it 'should intersect two ranges' do
    r1=Range.new(100,200)
    r2=Range.new(150,250)
    (r1&r2).should == Range.new(150,200)
  end
end

# BAD tests - internal testing. replace by IndexedIterator tests
describe 'CSV driver' do

  after :all do
    system "rm hoplang.log* hopsa.conf"
  end

  before :all do
    system 'ln -s tests/hopsa_test.conf hopsa.conf'
  end

  it 'should load two csv in, belongs to range 100..250' do
    ranges=[Range.new(100,200), Range.new(150,250)]
    #h=Hopsa::PlainHopstance.new('.', ranges,'f',nil,nil)

    files=Hopsa::CsvdirDBDriver::IndexedIterator.get_files(ROOT,ranges)
    files.should == ["#{ROOT}/100.csv","#{ROOT}/200.csv"]
  end

  it 'should load no files if ranges not cover them' do
    ranges=[Range.new(10,50), Range.new(30,99)]
    files=Hopsa::CsvdirDBDriver::IndexedIterator.get_files(ROOT,ranges)
    files.should == []
  end

  it 'should read proper test data' do
    ex=load_file('tests/csv_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.grep(/999997,999998/).size.should > 0
  end
end
