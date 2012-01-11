module Hopsa
  class Config
    CONFIG_FILE='./hopsa.conf'

    class << self
      def load
        @data=YAML.load(File.open(CONFIG_FILE, "r"))
        warn "CONFIG YAML: #{@data.inspect}"
      end

      def [](key)
        begin
#          warn "CONFIG: #{key}=#{@data[key]}"
          return @data[key]
        rescue
          warn "Warning: config key '#{key}' not found"
          return nil
        end
      end

      def varmap
        return @data["varmap"]
      end
    end
  end
end

