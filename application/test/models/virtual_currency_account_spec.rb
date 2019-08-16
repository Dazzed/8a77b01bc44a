# frozen_string_literal: true

describe VirtualCurrencyAccount do
  context "db columns" do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :balance }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  context "relationships" do
    it { expect(subject).to belong_to(:user) }
    it { expect(subject).to have_many(:owner_transactions) }
    it { expect(subject).to have_many(:giftee_transactions) }
  end
end
