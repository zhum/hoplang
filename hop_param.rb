# coding: utf-8
module Hopsa

  # gets command-line arguments
  class Param

    @@cmd_args = {}

    # loads parameter values from command line; currently, each parameter of the
    # form 'name=value' (no spaces!) is treated as parameter value
    # specification. However, only those parameters declared in the program,
    # either in param clause or in config file, can be used by the program
    def self.load
      ARGV.each do |arg|
        if arg =~ /([^=]+)=(.+)/
          @@cmd_args[$~[1]] = $~[2]
        end
      end
    end

    # gets argument value specified on the command line (if any)
    def self.cmd_arg_val(par_name)
      @@cmd_args[par_name]
    end

  end

end
