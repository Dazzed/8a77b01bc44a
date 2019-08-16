# frozen_string_literal: true

describe UserJobLock do
  let(:user) { Fabricate(:user) }

  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :last_updated_to_localytics }
    it { expect(subject).to have_db_column :last_updated_to_customerio }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:user) }
  end
end
