require 'bricolage/filesystem'
require 'bricolage/datasource'
require 'bricolage/variables'
require 'bricolage/configloader'
require 'bricolage/logger'
require 'bricolage/exception'
require 'forwardable'

module Bricolage

  class Context
    DEFAULT_ENV = 'development'

    def Context.environment(opt_env = nil)
      opt_env || ENV['BRICOLAGE_ENV'] || DEFAULT_ENV
    end

    def Context.home_path(opt_path = nil)
      FileSystem.home_path(opt_path)
    end

    def Context.for_application(home_path = nil, job_path_0 = nil, job_path: nil, environment: nil, global_variables: nil, logger: nil)
      env = environment(environment)
      if (job_path ||= job_path_0)
        fs = FileSystem.for_job_path(job_path, env)
        if home_path and home_path.realpath.to_s != fs.home_path.realpath.to_s
          raise OptionError, "--home option and job file is exclusive"
        end
      else
        fs = FileSystem.for_options(home_path, env)
      end
      load(fs, env, global_variables: global_variables, logger: logger)
    end

    def Context.load(fs, env, global_variables: nil, data_sources: nil, logger: nil)
      new(fs, env, global_variables: global_variables, logger: logger).tap {|ctx|
        ctx.load_configurations
      }
    end
    private_class_method :load

    def initialize(fs, env, global_variables: nil, data_sources: nil, logger: nil)
      @logger = logger || Logger.default
      @filesystem = fs
      @environment = env
      @opt_global_variables = global_variables || Variables.new
      @data_sources = data_sources
    end

    def load_configurations
      @filesystem.config_pathes('prelude.rb').each do |path|
        EmbeddedCodeAPI.module_eval(File.read(path)) if path.exist?
      end
      @data_sources = DataSourceFactory.load(self, @logger)
    end

    attr_reader :environment
    attr_reader :logger

    def get_data_source(type, name)
      @data_sources.get(type, name)
    end

    def subsystem(id)
      self.class.new(@filesystem.subsystem(id), @environment,
        global_variables: @opt_global_variables,
        data_sources: @data_sources,
        logger: @logger)
    end

    extend Forwardable
    def_delegators '@filesystem',
      :scoped?,
      :home_path,
      :root_relative_path,
      :config_path,
      :config_pathes,
      :job_dir,
      :job_file,
      :parameter_file,
      :parameter_file_loader

    #
    # Variables
    #

    def global_variables
      Variables.union(
        builtin_variables,
        load_global_variables,
        @opt_global_variables
      )
    end

    def builtin_variables
      Variables.define {|vars|
        vars['bricolage_env'] = @environment
        vars['bricolage_home'] = home_path.to_s
      }
    end

    def load_global_variables
      subsys_path = scoped? ? [@filesystem.relative(GLOBAL_VARIABLE_FILE)] : []
      vars_list = (config_pathes(GLOBAL_VARIABLE_FILE) + subsys_path).map {|path|
        path.exist? ? load_variables(path) : nil
      }
      Variables.union(*vars_list.compact)
    end

    GLOBAL_VARIABLE_FILE = 'variable.yml'

    def load_variables(path)
      Variables.define {|vars|
        @filesystem.config_file_loader.load_yaml(path).each do |name, value|
          vars[name] = value
        end
      }
    end
    private :load_variables
  end

end
