module UISamples

  # WARNING: This port is incomplete now.
  class JavaScriptProxy < BaseAction
    description "[NOT YET] Use JavaScript proxy objects to access server-side Java objects from inside the browser."

    def initialize
      @i = 0
    end

    # TODO: let stapler recognize it.
    def increment(n)
      @i += n
    end
  end
end

Jenkins::Plugin.instance.register_extension(UISamples::JavaScriptProxy)
