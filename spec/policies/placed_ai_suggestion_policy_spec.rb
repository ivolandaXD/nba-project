# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlacedAiSuggestionPolicy do
  let(:user) { create(:user) }
  let(:other) { create(:user) }
  let(:placed) { create(:placed_ai_suggestion, user: user) }

  it 'allows index for signed-in users' do
    expect(described_class.new(user, PlacedAiSuggestion).index?).to be true
  end

  it 'denies index for guests' do
    expect(described_class.new(nil, PlacedAiSuggestion).index?).to be false
  end

  it 'allows update only for owner' do
    expect(described_class.new(user, placed).update?).to be true
    expect(described_class.new(other, placed).update?).to be false
    expect(described_class.new(nil, placed).update?).to be false
  end
end
