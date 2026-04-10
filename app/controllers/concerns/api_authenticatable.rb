module ApiAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_from_token!
  end

  private

  def authenticate_from_token!
    token = bearer_token
    @current_user = User.find_by(api_token: token) if token.present?
    render json: { error: 'Unauthorized' }, status: :unauthorized unless @current_user
  end

  def bearer_token
    header = request.headers['Authorization'].to_s
    return Regexp.last_match(1) if header =~ /\ABearer (.+)\z/

    request.headers['X-Api-Token'].presence
  end

  def current_user
    @current_user
  end
end
