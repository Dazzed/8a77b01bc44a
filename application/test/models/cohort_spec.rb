# frozen_string_literal: true

describe Cohort, type: :model do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :name }
    it { expect(subject).to have_db_column :description }
    it { expect(subject).to have_db_column :active }
    it { expect(subject).to have_db_column :data }
    it { expect(subject).to have_db_column :paywall_product_type_id }
    it { expect(subject).to have_db_column :referral_product_type_id }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:paywall) }
    it { expect(subject).to belong_to(:referral) }
    it { expect(subject).to have_and_belong_to_many(:tiers) }
    it { expect(subject).to have_many(:user_settings) }
  end

  describe 'scopes' do
    it 'offers retrieving only active cohorts' do
      expect(Cohort.active.to_sql).to eq Cohort.all.where(active: true).to_sql
    end
  end

  describe 'default values' do
    it { expect(subject.active).to eq false }
  end

  describe 'data store' do
    describe 'defaults' do
      it 'sets properly' do
        expect(subject.onboard_trial_active).to eq CONFIG[:onboard_trial_active]
        expect(subject.override_all_subscriptions).to eq CONFIG[:override_all_subscriptions]
      end
    end

    describe 'explicit creation' do
      [true, false].each do |bool|
        it "returns #{bool} correctly" do
          cohort = Fabricate.build(:cohort, data: { onboard_trial_active: bool, override_all_subscriptions: bool })
          cohort.save!
          cohort.reload
          expect(cohort.onboard_trial_active).to eq bool
          expect(cohort.override_all_subscriptions).to eq bool
        end
      end
    end
  end
end
