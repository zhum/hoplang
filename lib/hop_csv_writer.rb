require 'logger'
require 'hoplang'
include Hopsa

$logger = Logger.new(STDERR)

class CsvDirWriter

  MAX_SAVE_COUNT=1000

  def initialize(source)
    cfg = Hopsa::Config['varmap'][source]
    raise "Not found config for #{source}" if cfg.nil?
    defcfg = Hopsa::Config['dbmap']['csvdir'] || Hash.new

    @split_field=cfg['split'] || defcfg['split']
    @root_dir=cfg['base_dir'] || defcfg['base_dir']
    if @root_dir.nil?
      @root_dir=cfg['dir']
    else
      @root_dir += '/'+source
    end
    @fields=cfg['fields'] || defcfg['fields']
    @saved_count=0
    @file=nil

    $logger.warn cfg.inspect
  end

  def put(data)
    @field_value = data[@split_field.to_sym].to_i.to_s

    if @saved_count>MAX_SAVE_COUNT
      @file.close
      @file=nil
    end

    if @file.nil?
      begin
        @file=File::open("#{@root_dir}/#{@field_value}.csv",'a')
      rescue Errno::ENOENT
#        puts ">>>> #{e.class} #{e.message}"
        Dir::mkdir @root_dir
      end
    end

    @file.puts @fields.map{ |index| data[index] }.join ';'
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
