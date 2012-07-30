#! /usr/bin/ruby
require 'rubygems'
require 'cassandra/0.8'

class CleoInserter

  # set up connection
  def initialize
    @hopsa = Cassandra.new 'hopsa', 'localhost:9160'
    @active = true
  end

  # parse time from c date-time
  def parse_time(ctime)
    dt = DateTime.parse ctime
    Time.local(dt.year, dt.month, dt.mday, dt.hour, dt.min, dt.sec, 0)
  end

  # transforms a value to a correct long string, which can be inserted into cassandra DB
  def to_long(val) 
    case val
    when Time
      #Cassandra::Long.new(val.tv_sec)
      Cassandra::Long.new(val.tv_sec).to_s
    when Integer
      #Cassandra::Long.new(val)
      Cassandra::Long.new(val).to_s
    else; 
      raise val.class.inspect + ': type cannot be converted to long'
    end
  end

  # transforms a value to a correct "string" to be stored as an integer
  def to_int(val) 
    to_long(val)[0,4]
  end

  # transforms a string read from Cassandra DB into a ruby integer value
  def int_to_integer(str)
    res = 0
    base = 256
    str.each_byte do |b|
      res = res * base + b
    end
    res
  end

  def long_to_integer(str)
    Cassandra::Long.new(str).to_i
    #long.to_i
  end

  def event_filter(event)
    true
    #event[:time].year == 2010
  end

  # gets the cassandra key for the event
  def key(event)
    event[:queue] + '-' + event[:sysid].inspect
  end

  # cleo event processing; event types are :ADDED, :RUN and :END_TASK; the event is a map, 
  # with fields relevant for the defined event. Fields are marked with symbols. The :time
  # field is always present, and equals to the time of the event. No fields are defined
  # for the event to be computed.

  # insert the event when the task has been added to the queue
  # event - the event info map
  def insert_added(event)
    #print 'insert added'
    return nil unless event_filter event
    caskey = key event
    casmap = {
      'cmdline' => event[:cmdline],
      'cputime' => to_long(0),
      'ncpus' => to_long(event[:ncpus]),
      'queue' => event[:queue], 
      'runtime' => to_long(0),
      'sysid' => to_long(event[:sysid]), 
      'tqueued' => to_long(event[:time]),
      'user' => event[:user],
      'waittime' => to_long(0),
      'tstart' => to_long(0),
      'tend' => to_long(0)
    }
    # print caskey
    # print casmap
    @hopsa.insert :tasks_cheb, caskey, casmap
  end

  # inserts the event when the task starts running
  def insert_run(event)
    # print 'insert run'
    return nil unless event_filter event
    caskey = key event
    dict = @hopsa.get(:tasks_cheb, caskey)
    return nil if dict == nil || dict.empty?
    tqueued = long_to_integer(dict['tqueued'])
    wait_time = event[:time].tv_sec - tqueued
    #print "event[:time].tv_sec = #{event[:time].tv_sec}"
    #print "tqueued = #{tqueued}"
    #print "wait_time = #{wait_time}"
    casmap = {
      'cputime' => to_long(0),
      'ncpus' => to_long(event[:ncpus]),
      'runtime' => to_long(0),
      'tstart' => to_long(event[:time]),
      'waittime' => to_long(wait_time)
    }
    # print casmap
    @hopsa.insert :tasks_cheb, caskey, casmap
  end

  # inserts the the end task event
  def insert_end(event)
    # print 'insert end'
    return nil unless event_filter event
    caskey = key event
    dict = @hopsa.get(:tasks_cheb, caskey)
    return nil if dict == nil || dict.empty?
    ncpus = long_to_integer(dict['ncpus'])
    tstart = long_to_integer(dict['tstart'])
    # print "tstart = #{tstart}"
    if tstart > 0
      # task ended normally
      casmap = {
        'cputime' => to_long((event[:time].tv_sec - tstart) * ncpus),
        'runtime' => to_long(event[:time].tv_sec - tstart),
        'tend' => to_long(event[:time])
      }
    else
      # task ended without ever starting
      tqueued = long_to_integer(dict['tqueued'])
      casmap = {
        'waittime' => to_long(event[:time].tv_sec - tqueued),
        'tend' => to_long(event[:time])
      }
    end
    # print casmap
    @hopsa.insert :tasks_cheb, caskey, casmap
  end

  # translates log event to database record
  def process_event(e)
      begin
        case e.type 
        when :added
          insert_added event if @active

        when :run
          insert_run event if @active

        when :end
          insert_end event if @active
        else; 
          # do nothing
        end
      rescue #Exception 
        print 'line ' + line_num.inspect + ': ' + $!
      end
    end
  end
end # CleoInserter

# main code
inserter = CleoInserter.new
#inserter.initialize
$\ = "\n"
$, = ", "
STDIN.each_line {|line|
  h=line.split(';')
  inserter.scan_log Hash[*h]
}

=begin

          event[:time] = parse_time $~[1]
          event[:queue] = $~[2]
          event[:sysid] = $~[3].to_i
          event[:user] = $~[4]
          event[:ncpus] = $~[5].to_i
          event[:cmdline] = $~[6]
=end
