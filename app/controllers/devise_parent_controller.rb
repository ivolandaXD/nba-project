class DeviseParentController < ActionController::Base
  protect_from_forgery with: :exception
  layout 'web'
end
