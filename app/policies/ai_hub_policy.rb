# frozen_string_literal: true

class AiHubPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def analyze?
    user&.admin?
  end
end
