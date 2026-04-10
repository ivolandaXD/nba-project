class ComparisonPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def teams?
    user.present?
  end

  def matchup?
    user.present?
  end
end
