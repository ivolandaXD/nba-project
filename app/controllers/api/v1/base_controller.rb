module Api
  module V1
    class BaseController < ApplicationController
      include ApiAuthenticatable

      def pundit_user
        current_user
      end
    end
  end
end
