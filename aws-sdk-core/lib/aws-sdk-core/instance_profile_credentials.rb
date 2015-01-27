require 'time'
require 'net/http'

module Aws
  class InstanceProfileCredentials < Credentials

    include RefreshingCredentials

    # @api private
    class Non200Response < RuntimeError; end

    # These are the errors we trap when attempting to talk to the
    # instance metadata service.  Any of these imply the service
    # is not present, no responding or some other non-recoverable
    # error.
    # @api private
    FAILURES = [
      Errno::EHOSTUNREACH,
      Errno::ECONNREFUSED,
      Errno::EHOSTDOWN,
      Errno::ENETUNREACH,
      SocketError,
      Timeout::Error,
      Non200Response,
    ]

    # @param [Hash] options
    # @option options [Integer] :retries (0) Number of times to retry
    #   when retrieving credentials.
    # @option options [String] :ip_address ('169.254.169.254')
    # @option options [Integer] :port (80)
    # @option options [Float] :http_open_timeout (1)
    # @option options [Float] :http_read_timeout (1)
    # @option options [IO] :http_debug_output (nil) HTTP wire
    #   traces are sent to this object.  You can specify something
    #   like $stdout.
    def initialize options = {}
      @retries = options[:retries] || 0
      @ip_address = options[:ip_address] || '169.254.169.254'
      @port = options[:port] || 80
      @http_open_timeout = options[:http_open_timeout] || 1
      @http_read_timeout = options[:http_read_timeout] || 1
      @http_debug_output = options[:http_debug_output]
      super
    end

    # @return [Integer] The number of times to retry failed atttempts to
    #   fetch credentials from the instance metadata service. Defaults to 0.
    attr_reader :retries

    private

    def refresh
      credentials = MultiJson.load(get_credentials)
      @access_key_id = credentials['AccessKeyId']
      @secret_access_key = credentials['SecretAccessKey']
      @session_token = credentials['Token']
      if expires = credentials['Expiration']
        @expiration = Time.parse(expires)
      else
        @expiration = nil
      end
    end

    def get_credentials
      failed_attempts = 0
      begin
        open_connection do |conn|
          path = '/latest/meta-data/iam/security-credentials/'
          profile_name = http_get(conn, path).lines.first.strip
          http_get(conn, path + profile_name)
        end
      rescue *FAILURES => e
        if failed_attempts < @retries
          backoff(failed_attempts)
          failed_attempts += 1
          retry
        else
          '{}'
        end
      end
    end

    def backoff(failed_attempts)
      Kernel.sleep(2 ** failed_attempts)
    end

    def open_connection
      http = Net::HTTP.new(@ip_address, @port, nil)
      http.open_timeout = @http_open_timeout
      http.read_timeout = @http_read_timeout
      http.set_debug_output(@http_debug_output) if @http_debug_output
      http.start
      yield(http).tap { http.finish }
    end

    def http_get(connection, path)
      response = connection.request(Net::HTTP::Get.new(path))
      if response.code.to_i == 200
        response.body
      else
        raise Non200Response
      end
    end

  end
end
