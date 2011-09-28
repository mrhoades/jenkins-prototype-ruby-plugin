# TODO: move to jenkins-plugin-runtime
module Jenkins
  module Model
    class Build
      def workspace
        @native.getWorkspace()
      end
    end
  end

  class Launcher

    class Proc
      def initialize(native)
        @native = native
      end

      def alive?
        @native.isAlive()
      end

      def join
        @native.join()
      end

      def kill
        @native.kill()
      end

      def stdin
        @native.getStdin().to_io
      end

      def stdout
        @native.getStdout().to_io
      end

      def stderr
        @native.getStderr().to_io
      end
    end

    # execute([env,] command... [,options]) -> fixnum
    def execute(*args)
      spawn(*args).join
    end

    # spawn([env,] command... [,options]) -> proc
    def spawn(*args)
      env, cmd, options = scan_args(args)
      starter = @native.launch()
      # env
      starter.envs(env)
      # options
      if opt_chdir = options[:chdir]
        starter.pwd(opt_chdir)
      end
      if opt_in = options[:in]
        starter.stdin(opt_in.to_inputstream)
      end
      if opt_out = options[:out]
        if opt_out.is_a?(Jenkins::Model::Listener)
          starter.stdout(Jenkins::Plugin.instance.export(opt_out))
        else
          starter.stdout(opt_out.to_outputstream)
        end
      end
      if opt_err = options[:err]
        starter.stderr(opt_err.to_outputstream)
      end
      # cmd
      case cmd
      when Array
        starter.cmds(cmd)
      else
        begin
          # when we are on 1.432, we can use cmdAsSingleString
          starter.cmdAsSingleString(cmd.to_s)
        rescue NoMethodError
          require 'shellwords'
          starter.cmds(*Shellwords.split(cmd.to_s))
        end
      end
      Proc.new(starter.start())
    end

  private

    def scan_args(args)
      if args.last
        if Hash === args.last
          opt = args.pop
        elsif args.last.respond_to?(:to_hash)
          opt = args.pop.to_hash
        end
      end
      if args.first
        if Hash === args.first
          env = args.shift
        elsif args.first.respond_to?(:to_hash)
          env = args.shift.to_hash
        end
      end
      if args.length == 1
        cmd = args.first
      else
        cmd = args
      end
      [env || {}, cmd, opt || {}]
    end
  end
end

require 'logger'
require 'shellwords'
require 'yaml'

class TravisScriptBuilder < Jenkins::Tasks::Builder

  display_name "Travis Builder"

  # TODO: better to use travis-worker instead of re-implementing it?
  def prebuild(build, listener)
    init(build, nil, listener)
    logger.info "Prebuild"

    travis_file = workspace_file('.travis.yml')
    unless travis_file.exists
      logger.error"Travis config `#{travis_file}' not found"
      raise "Travis config file not found"
    end
    logger.info "Found travis file: " + travis_file.to_s
    @config = YAML.load(travis_file.read.to_io.read)

    @gemfile = @config['gemfile'] || 'Gemfile'
    @gemfile = nil unless workspace_file(@gemfile).exists
    @config['script'] ||= @gemfile ? "bundle exec rake" : 'rake'

    logger.info "Prebuild finished"
  end

  def perform(build, launcher, listener)
    init(build, launcher, listener)
    logger.info "Build"

    env = setup_env
    install_dependencies
    run_scripts(env)

    logger.info "Build finished"
  end

private

  def init(build, launcher, listener)
    @build, @launcher, @listener = build, launcher, listener
    @logger = JenkinsListenerLogger.new(@listener, display_name)
  end

  def logger
    @logger
  end

  def workspace_file(file)
    @build.workspace.child(file)
  end

  def setup_env
    env = {}
    if @gemfile
      env['BUNDLE_GEMFILE'] = @gemfile
    end
    Array(@config['env']).each do |line|
      key, value = line.split(/\s*=\s*/, 2)
      env[key] = value
    end
    logger.info "Additional environment variable(s): #{env.inspect}"
    env
  end

  def install_dependencies
    if @gemfile
      # TODO: we should have common gem repository
      env = {'BUNDLE_PATH' => '.'}
      script = "bundle install"
      script += " #{@config['bundler_args']}" if @config['bundler_args']
      exec(env, script)
    end
  end

  def run_scripts(env)
    %w{before_script script after_script}.each do |type|
      next unless @config.key?(type)
      logger.info "Start #{type}: " + @config[type]
      scan_multiline_scripts(@config[type]).each do |script|
        exec(env, script)
      end
    end
  end

  def scan_multiline_scripts(script)
    case script
    when Array
      script
    else
      script.to_s.split("\n")
    end
  end

  # TODO: It uses Shellwords module but isn't there a easy way to do
  #   -> when we depend on 1.432, use cmdAsSingleString
  # 'command execution as a whole String'?
  # http://d.hatena.ne.jp/sikakura/20110324/1300977208 is doing
  # Arrays.asList(str.split(" ")) which should be wrong.
  def exec(env, command)
    logger.info "Launching command: #{command}, with environment: #{env.inspect}"
    result = @launcher.execute(command, :chdir => @build.workspace, :out => @listener)
    logger.info "Command execution finished with #{result}"
    raise "command execution failed" if result != 0
  end

  class JenkinsListenerLogger < Logger
    class JenkinsListenerIO
      def initialize(listener)
        @listener = listener
      end

      def write(msg)
        @listener.log(msg)
      end

      def close
        # do nothing for imported device
      end
    end

    def initialize(listener, progname)
      super(JenkinsListenerIO.new(listener))
      self.progname = progname
    end
  end
end
