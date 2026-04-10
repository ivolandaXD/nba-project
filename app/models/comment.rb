class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :game

  validates :content, presence: true, length: { maximum: 5000 }

  before_validation :sanitize_content

  private

  def sanitize_content
    return if content.blank?

    self.content = ActionController::Base.helpers.sanitize(
      content,
      tags: %w[b i em strong a p br],
      attributes: %w[href]
    ).strip
  end
end
