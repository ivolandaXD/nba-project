class SeasonStatsPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def sync?
    user&.admin?
  end

  def predict?
    user.present?
  end
end
