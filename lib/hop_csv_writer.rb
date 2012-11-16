require 'logger'
require 'hoplang'
include Hopsa

$logger = Logger.new(STDERR)

class CsvDirWriter

  MAX_SAVE_COUNT=1000

  def initialize(source)
    cfg = Hopsa::Config['varmap'][source]
    raise "Not found config for #{source}" if cfg.nil?

    @split_field=cfg['split']
    @root_dir=cfg['dir']
    @fields=cfg['fields'].map {|x| x.to_s}
    @saved_count=0
    @file=nil

    $logger.warn cfg.inspect
  end

  def put(data)
    @field_value = data[@split_field.to_s].to_i.to_s

    if @saved_count>MAX_SAVE_COUNT
      @file.close
      @file=nil
    end

    if @file.nil?
      first_attempt=true
      begin
        @file=File::open("#{@root_dir}/#{@field_value}.csv",'a')
      rescue Errno::ENOENT => e
#        puts ">>>> #{e.class} #{e.message}"
        raise e unless first_attempt
        Dir::mkdir @root_dir
        first_attempt=false
        retry
      end
    end

#    $logger.warn @fields.map{ |index| index.to_s }.join ';'
#    $logger.puts @fields.map{ |index| data[index.to_s] }.join ';'
#    $logger.warn data.inspect
#    exit 0
    @file.puts @fields.map{ |index| data[index.to_s] }.join ';'
  end

  def close
    @file.nil? || @file.close
  end
end

if __FILE__ == $0
  Hopsa::Config.load
  Hopsa::Param.load
  Hopsa::Function.load

  writer = CsvDirWriter.new('cpu_user_c')
  1.upto 1000 do |i|
    x={'node' => "node-#{i/20}", 'value' => "#{i%100}", 'time' => 1234567+i, 'n' => 0}
    writer.put  x
  end
  $logger.warn "1000 values written"
end
