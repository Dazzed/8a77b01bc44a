require 'rails_helper'

RSpec.describe FriendStory, type: :model do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :external_media_url }
    it { expect(subject).to have_db_column :media }
    it { expect(subject).to have_db_column :media_type }
    it { expect(subject).to have_db_column :text }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  context "relationships" do
    it { expect(subject).to belong_to(:user) }
  end
end
