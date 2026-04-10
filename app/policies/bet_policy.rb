class BetPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user.present?
  end

  def update?
    user.present? && record.user_id == user.id
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(user: user)
    end
  end
end
