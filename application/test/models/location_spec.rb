# frozen_string_literal: true

describe Location do
  context "db columns" do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :city }
    it { expect(subject).to have_db_column :state_province }
    it { expect(subject).to have_db_column :postal_code }
    it { expect(subject).to have_db_column :country }
    it { expect(subject).to have_db_column :country_code }
    it { expect(subject).to have_db_column :latitude }
    it { expect(subject).to have_db_column :longitude }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  context "relationships" do
    it { expect(subject).to have_one(:user) }
  end
end
