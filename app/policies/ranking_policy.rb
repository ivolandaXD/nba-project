class RankingPolicy < ApplicationPolicy
  def index?
    user.present?
  end
end
