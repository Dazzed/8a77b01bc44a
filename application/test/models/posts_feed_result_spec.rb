# frozen_string_literal: true

describe PostsFeedResult, type: :model do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :num_results }
    it { expect(subject).to have_db_column :gender_filter }
    it { expect(subject).to have_db_column :location_filter }
    it { expect(subject).to have_db_column :time_filter }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:user) }
  end
end
