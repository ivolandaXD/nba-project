# frozen_string_literal: true

class PlacedAiSuggestionPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def update?
    user.present? && record.user_id == user.id
  end

  def ai_post_mortem?
    update?
  end
end
