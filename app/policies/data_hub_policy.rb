# frozen_string_literal: true

class DataHubPolicy < ApplicationPolicy
  def index?
    user.present?
  end
end
