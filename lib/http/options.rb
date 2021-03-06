require "http/headers"
require "openssl"
require "socket"
require "http/cache/null_cache"
require "http/uri"

module HTTP
  class Options
    @default_socket_class     = TCPSocket
    @default_ssl_socket_class = OpenSSL::SSL::SSLSocket

    @default_timeout_class = HTTP::Timeout::Null

    @default_cache = Http::Cache::NullCache.new

    class << self
      attr_accessor :default_socket_class, :default_ssl_socket_class
      attr_accessor :default_cache, :default_timeout_class

      def new(options = {})
        return options if options.is_a?(self)
        super
      end

      def defined_options
        @defined_options ||= []
      end

      protected

      def def_option(name, &interpreter)
        defined_options << name.to_sym
        interpreter ||= lambda { |v| v }

        attr_accessor name
        protected :"#{name}="

        define_method(:"with_#{name}") do |value|
          dup { |opts| opts.send(:"#{name}=", instance_exec(value, &interpreter)) }
        end
      end
    end

    def initialize(options = {})
      defaults = {:response =>         :auto,
                  :proxy =>            {},
                  :timeout_class =>    self.class.default_timeout_class,
                  :timeout_options =>  {},
                  :socket_class =>     self.class.default_socket_class,
                  :ssl_socket_class => self.class.default_ssl_socket_class,
                  :ssl =>              {},
                  :cache =>            self.class.default_cache,
                  :keep_alive_timeout  => 5,
                  :headers =>          {}}

      opts_w_defaults = defaults.merge(options)
      opts_w_defaults[:headers] = HTTP::Headers.coerce(opts_w_defaults[:headers])

      opts_w_defaults.each do |(opt_name, opt_val)|
        self[opt_name] = opt_val
      end
    end

    def_option :headers do |headers|
      self.headers.merge(headers)
    end

    %w(
      proxy params form json body follow response
      socket_class ssl_socket_class ssl_context ssl
      persistent keep_alive_timeout timeout_class timeout_options
    ).each do |method_name|
      def_option method_name
    end

    def follow=(value)
      @follow = case
                when !value                    then nil
                when true == value             then {}
                when value.respond_to?(:fetch) then value
                else argument_error! "Unsupported follow options: #{value}"
                end
    end

    def persistent=(value)
      @persistent = value ? HTTP::URI.parse(value).origin : nil
    end

    def persistent?
      !persistent.nil?
    end

    def_option :cache do |cache_or_cache_options|
      if cache_or_cache_options.respond_to? :perform
        cache_or_cache_options
      else
        require "http/cache"
        HTTP::Cache.new(cache_or_cache_options)
      end
    end

    def [](option)
      send(option) rescue nil
    end

    def merge(other)
      h1, h2 = to_hash, other.to_hash
      merged = h1.merge(h2) do |k, v1, v2|
        case k
        when :headers
          v1.merge(v2)
        else
          v2
        end
      end

      self.class.new(merged)
    end

    def to_hash
      hash_pairs = self.class.
                   defined_options.
                   flat_map { |opt_name| [opt_name, self[opt_name]] }
      Hash[*hash_pairs]
    end

    def dup
      dupped = super
      yield(dupped) if block_given?
      dupped
    end

    protected

    def []=(option, val)
      send(:"#{option}=", val)
    end

    private

    def argument_error!(message)
      fail(Error, message, caller[1..-1])
    end
  end
end
