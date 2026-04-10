class PlayerPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  def fetch_game_logs?
    user&.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
