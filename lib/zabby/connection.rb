module Zabby
  class Connection

    API_OUTPUT_SHORTEN = "shorten"
    API_OUTPUT_REFER = "refer"
    API_OUTPUT_EXTEND = "extend"


    attr_reader :uri, :request_path, :user, :password, :proxy_host, :proxy_user, :proxy_password
    attr_reader :auth
    attr_reader :request_id

    def initialize
      reset
    end

    def reset
      @uri = @user = @password = @proxy_host = @proxy_user = @proxy_password = nil
      @request_id = 0
      @auth = nil
    end

    def login(config)
      @uri = URI.parse(config[:host])
      @user = config[:user]
      @password = config[:password]
      if config[:proxy_host]
        @proxy_host = URI.parse(config[:proxy_host])
        @proxy_user = config[:proxy_user]
        @proxy_password = config[:proxy_password]
      end
      @request_path = @uri.path.empty? ? "/api_jsonrpc.php" : @uri.path
      authenticate
    end

    def logout
      reset
    end

    def logged_in?
      !@auth.nil?
    end
    
    def next_request_id
      @request_id += 1
    end

    # @return [Authentication key]
    def authenticate
      auth_message = format_message('user', 'login',
                                    'user' => @user,
                                    'password' => @password)
      @auth = query_zabbix_rpc(auth_message)
    rescue Exception => e
      @auth = nil
      raise e
    end

    def format_message(element, action, params = {})
      {
          'jsonrpc' => '2.0',
          'id' => next_request_id,
          'method' => "#{element}.#{action}",
          'params' => { :output=>API_OUTPUT_EXTEND }.merge(params),
          'auth' => @auth
      }
    end

    def perform_request(element, action, params)
      raise AuthenticationError.new("Not logged in") if !logged_in?

      message = format_message(element, action, params)
      query_zabbix_rpc(message)
    end

    def query_zabbix_rpc(message)
      request = Net::HTTP::Post.new(@request_path)
      request.add_field('Content-Type', 'application/json-rpc')
      request.body = JSON.generate(message)

      if @proxy_host
        http = Net::HTTP::Proxy(@proxy_host.host, @proxy_host.port, @proxy_user, @proxy_password).new(@uri.host, @uri.port)
      else
        http = Net::HTTP.new(@uri.host, @uri.port)
      end
      if @uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      # Send the request!
      response = http.request(request)

      if response.code != "200" then
        raise ResponseCodeError.new("Response code from [#{@api_url}] is #{response.code})")
      end

      zabbix_response = JSON.parse(response.body)

      #if not ( responce_body_hash['id'] == id ) then
      # raise Zabbix::InvalidAnswerId.new("Wrong ID in zabbix answer")
      #end

      # Check errors in zabbix answer. If error exist - raise exception Zabbix::Error
      if (error = zabbix_response['error']) then
        error_message = error['message']
        error_data = error['data']
        error_code = error['code']

        e_message = "Code: [" + error_code.to_s + "]. Message: [" + error_message +
                "]. Data: [" + error_data + "]."

        if error_data == "Login name or password is incorrect"
          raise AuthenticationError.new(e_message)
        else
          raise StandardError.new(e_message)
        end
      end

      zabbix_response['result']
    end
  end
end