module Liquid

  # Templates are central to liquid.
  # Interpretating templates is a two step process. First you compile the
  # source code you got. During compile time some extensive error checking is performed.
  # your code should expect to get some SyntaxErrors.
  #
  # After you have a compiled template you can then <tt>render</tt> it.
  # You can use a compiled template over and over again and keep it cached.
  #
  # Example:
  #
  #   template = Liquid::Template.parse(source)
  #   template.render('user_name' => 'bob')
  #
  class Template
    DEFAULT_OPTIONS = {
      :locale => I18n.new
    }

    attr_accessor :root, :resource_limits
    @@file_system = BlankFileSystem.new

    class TagRegistry
      def initialize
        @tags  = {}
        @cache = {}
      end

      def [](tag_name)
        return nil unless @tags.has_key?(tag_name)
        return @cache[tag_name] if Liquid.cache_classes

        lookup_class(@tags[tag_name]).tap { |o| @cache[tag_name] = o }
      end

      def []=(tag_name, klass)
        @tags[tag_name]  = klass.name
        @cache[tag_name] = klass
      end

      def delete(tag_name)
        @tags.delete(tag_name)
        @cache.delete(tag_name)
      end

      private

      def lookup_class(name)
        name.split("::").reject(&:empty?).reduce(Object) { |scope, const| scope.const_get(const) }
      end
    end

    class << self
      # Sets how strict the parser should be.
      # :lax acts like liquid 2.5 and silently ignores malformed tags in most cases.
      # :warn is the default and will give deprecation warnings when invalid syntax is used.
      # :strict will enforce correct syntax.
      attr_writer :error_mode

      def file_system
        @@file_system
      end

      def file_system=(obj)
        @@file_system = obj
      end

      def register_tag(name, klass)
        tags[name.to_s] = klass
      end

      def tags
        @tags ||= TagRegistry.new
      end

      def error_mode
        @error_mode || :lax
      end

      # Pass a module with filter methods which should be available
      # to all liquid views. Good for registering the standard library
      def register_filter(mod)
        Strainer.global_filter(mod)
      end

      # creates a new <tt>Template</tt> object from liquid source code
      def parse(source, options = {})
        template = Template.new
        template.parse(source, options)
      end
    end

    # creates a new <tt>Template</tt> from an array of tokens. Use <tt>Template.parse</tt> instead
    def initialize
      @resource_limits = {}
    end

    # Parse source code.
    # Returns self for easy chaining
    def parse(source, options = {})
      @root = Document.parse(tokenize(source), DEFAULT_OPTIONS.merge(options))
      @warnings = nil
      self
    end

    def warnings
      return [] unless @root
      @warnings ||= @root.warnings
    end

    def registers
      @registers ||= {}
    end

    def assigns
      @assigns ||= {}
    end

    def instance_assigns
      @instance_assigns ||= {}
    end

    def errors
      @errors ||= []
    end

    # Render takes a hash with local variables.
    #
    # if you use the same filters over and over again consider registering them globally
    # with <tt>Template.register_filter</tt>
    #
    # Following options can be passed:
    #
    #  * <tt>filters</tt> : array with local filters
    #  * <tt>registers</tt> : hash with register variables. Those can be accessed from
    #    filters and tags and might be useful to integrate liquid more with its host application
    #
    def render(*args)
      return ''.freeze if @root.nil?

      context = case args.first
      when Liquid::Context
        c = args.shift
        c.rethrow_errors = true if @rethrow_errors
        c
      when Liquid::Drop
        drop = args.shift
        drop.context = Context.new([drop, assigns], instance_assigns, registers, @rethrow_errors, @resource_limits)
      when Hash
        Context.new([args.shift, assigns], instance_assigns, registers, @rethrow_errors, @resource_limits)
      when nil
        Context.new(assigns, instance_assigns, registers, @rethrow_errors, @resource_limits)
      else
        raise ArgumentError, "Expected Hash or Liquid::Context as parameter"
      end

      case args.last
      when Hash
        options = args.pop

        if options[:registers].is_a?(Hash)
          self.registers.merge!(options[:registers])
        end

        if options[:filters]
          context.add_filters(options[:filters])
        end

      when Module
        context.add_filters(args.pop)
      when Array
        context.add_filters(args.pop)
      end

      begin
        # render the nodelist.
        # for performance reasons we get an array back here. join will make a string out of it.
        result = @root.render(context)
        result.respond_to?(:join) ? result.join : result
      rescue Liquid::MemoryError => e
        context.handle_error(e)
      ensure
        @errors = context.errors
      end
    end

    def render!(*args)
      @rethrow_errors = true
      render(*args)
    end

    private

    # Uses the <tt>Liquid::TemplateParser</tt> regexp to tokenize the passed source
    def tokenize(source)
      source = source.source if source.respond_to?(:source)
      return [] if source.to_s.empty?
      tokens = source.split(TemplateParser)

      # removes the rogue empty element at the beginning of the array
      tokens.shift if tokens[0] and tokens[0].empty?

      tokens
    end

  end
end
