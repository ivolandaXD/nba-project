# Retries for timeouts, conexão e HTTP 5xx / 429.
module HttpClient
  RETRY_EXCEPTIONS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Timeout::Error,
    Errno::ETIMEDOUT,
    Errno::ECONNRESET,
    SocketError,
    EOFError
  ].freeze

  DEFAULT_ATTEMPTS = 3
  DEFAULT_SLEEP = 0.45

  def self.with_retry(attempts: DEFAULT_ATTEMPTS, base_sleep: DEFAULT_SLEEP)
    last_response = nil
    attempts.times do |i|
      last_response = yield
      code = last_response.respond_to?(:code) ? last_response.code.to_i : 200
      if (code >= 500 && code < 600) || code == 429
        sleep(base_sleep * (i + 1)) if i < attempts - 1
        next if i < attempts - 1
      end
      return last_response
    rescue *RETRY_EXCEPTIONS
      sleep(base_sleep * (i + 1)) if i < attempts - 1
      raise if i >= attempts - 1
    end
    last_response
  end
end
