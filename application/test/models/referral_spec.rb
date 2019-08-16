require 'rails_helper'

RSpec.describe Referral, type: :model do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :referred_by_device_id }
    it { expect(subject).to have_db_column :device_id }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  context "relationships" do
    it { expect(subject).to belong_to(:referred_by_device) }
    it { expect(subject).to belong_to(:device) }
  end
end
