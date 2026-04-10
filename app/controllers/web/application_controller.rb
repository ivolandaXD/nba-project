module Web
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    layout 'web'

    helper Web::ApplicationHelper

    before_action :authenticate_user!

    include Pundit::Authorization

    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    private

    def pundit_user
      current_user
    end

    def user_not_authorized
      flash[:alert] = 'Acesso negado.'
      redirect_to(request.referer.presence || root_path)
    end
  end
end
