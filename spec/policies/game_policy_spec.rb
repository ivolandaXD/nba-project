require 'rails_helper'

RSpec.describe GamePolicy do
  let(:game) { build(:game) }

  it 'allows authenticated users to list and view' do
    user = create(:user)
    expect(described_class.new(user, Game).index?).to be true
    expect(described_class.new(user, game).show?).to be true
  end

  it 'denies guests' do
    expect(described_class.new(nil, Game).index?).to be false
  end

  it 'allows only admins to fetch odds and run AI' do
    admin = create(:user, :admin)
    user = create(:user)
    expect(described_class.new(admin, game).fetch_odds?).to be true
    expect(described_class.new(admin, game).analyze?).to be true
    expect(described_class.new(user, game).fetch_odds?).to be false
    expect(described_class.new(user, game).analyze?).to be false
  end
end
