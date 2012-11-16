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
 #   system "rm hoplang.log* hopsa.conf"
  end

  before :all do
    system 'ln -s tests/hopsa_test.conf hopsa.conf'
  end

  it 'do load two csv in, belongs to range 100..250' do
    ranges=[Range.new(100,200), Range.new(150,250)]
    #h=Hopsa::PlainHopstance.new('.', ranges,'f',nil,nil)

    files=Hopsa::CsvdirDBDriver::IndexedIterator.get_files(ROOT,ranges)
    files.should == ["#{ROOT}/100.csv","#{ROOT}/200.csv"]
  end

  it 'do load no files if ranges not cover them' do
    ranges=[Range.new(10,50), Range.new(30,99)]
    files=Hopsa::CsvdirDBDriver::IndexedIterator.get_files(ROOT,ranges)
    files.should == []
  end

  it 'do read proper test data' do
#    pending
    ex=load_file('tests/csv_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.grep(/999997,999998/).size.should == 1
    Hopsa::OUT.grep(/998000/).size.should == 0
  end
end

describe 'HopLang sytax contructions' do
  it 'does aggregation' do
    ex=load_file('tests/agg_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.grep(/98.0,200.0,149.0/).size.should == 1
  end

  it 'does grouping' do
    ex=load_file('tests/group_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.grep(/vasya6,111.0/).size.should == 1
  end

  it 'properly includes ins' do
    ex=load_file('tests/ins_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.size.should == 15
    Hopsa::OUT.grep(/node1-128-11,11/).size.should == 1
  end

  it 'works with nested hopstances' do
    ex=load_file('tests/nested_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.size.should == 1132
    Hopsa::OUT.grep(/node-55,-10.0,1,222,yyy/).size.should == 26
    Hopsa::OUT.grep(/node-2,45,1234612,11111,nnnnnnnnn/).size.should == 1
    Hopsa::OUT.grep(/node-2,45,1234612,1,vasya1/).size.should == 1
  end

  it 'works with parameters' do
    ex=load_file('tests/param_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.size.should == 21
    Hopsa::OUT.grep(/1234605,node-1,38/).size.should == 1
  end

  it 'prints two streams' do
    ex=load_file('tests/print_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.size.should == 398
    Hopsa::OUT.grep(/vasya99,299,out2/).size.should == 1
  end

  it 'sorts streams' do
    ex=load_file('tests/union_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.size.should == 40
  end

  it 'joins streams' do
    ex=load_file('tests/sort_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT[1].should == "vasya_16,84"
    Hopsa::OUT[85].should == "vasya_100,0"
  end

  it 'computes top' do
    ex=load_file('tests/top_test.hpl',:stdout => false)
    ex.hop
    Hopsa::OUT.size.should == 6
    Hopsa::OUT[1].should == "vasya25,125.0"
    Hopsa::OUT[5].should == "vasya21,121.0"
  end
end
