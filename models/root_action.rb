# Ad-hoc extension for jenkins-plugin-runtime
# TODO: Move to jenkins-plugin-runtime
module Jenkins
  module Actions
    class RootAction
      include Jenkins::Model::Action

      # TODO: Move to Jenkins::Model::Action?
      def url_name
        self.class.name
      end
    end
  end
end

module Jenkins
  class Plugin
    class Proxies
      class RootAction
        include Java.hudson.model.RootAction
        include Java.jenkins.ruby.DoDynamic
        include Jenkins::Plugin::Proxy

        def getDisplayName
          @object.display_name
        end

        def getIconFileName
          @object.icon
        end

        def getUrlName
          @object.url_name
        end

        # TODO: must convert to Rack interface
        def doDynamic(request, response)
          @object.doDynamic(request, response)
        end
      end

      register Jenkins::Actions::RootAction, RootAction
    end
  end
end

module Jenkins
  class Plugin
    # TODO: how many other extension points other than RootAction?
    def register_root_action(action)
      @peer.addExtension(export(action))
    end
  end
end

# Plugin part
class TestRootAction < Jenkins::Actions::RootAction
  display_name "Test Root Action"

  def icon
    "gear.png"
  end

  def url_name
    "root_action"
  end

  # TODO: the direct interface is temporarily
  def doDynamic(request, response)
    response.getWriter().println("path: " + request.getRestOfPath())
  end
end

require 'webrick'
require 'logger'
class DirectoryListingRootAction < Jenkins::Actions::RootAction
  display_name "Directory Listing"

  def initialize(root = File.dirname(__FILE__))
    @logger = Logger.new(STDERR)
    @config = {
      :HTTPVersion => '1.1',
      :Logger => @logger,
    }
    server = Struct.new(:config).new
    server.config = @config
    @servlet = WEBrick::HTTPServlet::FileHandler.new(server, root, :FancyIndexing => true)
  end

  def icon
    "folder.png"
  end

  def url_name
    "dir"
  end

  def doDynamic(request, response)
    begin
      req = WEBrick::HTTPRequest.new(@config)
      req.path_info = ""
      req.script_name = ""
      req.instance_variable_set("@path", request.getPathInfo())
      res = WEBrick::HTTPResponse.new(@config)
      @servlet.do_GET(req, res)
      res.send_body(str = '')
      response.getWriter().print(str)
    rescue Exception => e
      @logger.error(e)
    end
  end
end

# TODO: manual registration looks uglish but it would be more flexible than auto registration. 
test = TestRootAction.new
dir = DirectoryListingRootAction.new(File.expand_path('..', File.dirname(__FILE__)))
Jenkins::Plugin.instance.register_root_action(test)
Jenkins::Plugin.instance.register_root_action(dir)