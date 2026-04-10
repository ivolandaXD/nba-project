class GamePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def fetch_odds?
    user&.admin?
  end

  def analyze?
    user&.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
