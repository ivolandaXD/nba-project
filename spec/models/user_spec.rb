require 'rails_helper'

RSpec.describe User, type: :model do
  it 'is valid with factory defaults' do
    expect(build(:user)).to be_valid
  end

  it 'rejects invalid role' do
    expect(build(:user, role: 'superuser')).not_to be_valid
  end
end
