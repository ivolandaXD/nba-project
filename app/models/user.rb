class User < ApplicationRecord
  ROLES = %w[admin user].freeze

  devise :database_authenticatable, :registerable,
         :recoverable, :validatable, :rememberable

  has_secure_token :api_token

  has_many :comments, dependent: :destroy
  has_many :bets, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :placed_ai_suggestions, dependent: :destroy

  validates :role, inclusion: { in: ROLES }

  def admin?
    role == 'admin'
  end
end
