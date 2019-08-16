require 'rails_helper'

RSpec.describe Device, type: :model do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :uuid }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :is_blacklisted }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

    context "relationships" do
      it { expect(subject).to belong_to(:user) }
    end
end
