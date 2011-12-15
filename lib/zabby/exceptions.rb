module Zabby
  class ResponseCodeError < StandardError; end
  class AuthenticationError < StandardError; end
  class ConfigurationError < StandardError; end
end