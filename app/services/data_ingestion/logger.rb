# frozen_string_literal: true

module DataIngestion
  module Logger
    module_function

    def log(tag, level: :info, message:, **extra)
      line = "[DataIngestion::#{tag}] #{message}"
      line += " #{extra.compact.to_json}" if extra.compact.any?
      Rails.logger.public_send(level, line)
    end
  end
end
