class BetPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user.present?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(user: user)
    end
  end
end
