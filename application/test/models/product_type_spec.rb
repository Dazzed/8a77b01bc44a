# frozen_string_literal: true

describe ProductType, type: :model do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :name }
    it { expect(subject).to have_db_column :description }
    it { expect(subject).to have_db_column :apple_product_id }
    it { expect(subject).to have_db_column :subscription_price }
    it { expect(subject).to have_db_column :subscription_period_type }
    it { expect(subject).to have_db_column :introductory_price }
    it { expect(subject).to have_db_column :introductory_period_type }
    it { expect(subject).to have_db_column :introductory_num_periods }
    it { expect(subject).to have_db_column :payupfront_price }
    it { expect(subject).to have_db_column :payupfront_duration }
    it { expect(subject).to have_db_column :enabled }
    it { expect(subject).to have_db_column :order }
    it { expect(subject).to have_db_column :badge_text }
    it { expect(subject).to have_db_column :payupfront }
    it { expect(subject).to have_db_column :paywall }
    it { expect(subject).to have_db_column :tiers }
    it { expect(subject).to have_db_column :referral }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to have_and_belong_to_many(:cohorts) }
  end

  describe 'scopes' do
    it 'offers retrieving only payupfront ProductTypes' do
      expect(ProductType.payupfront.to_sql).to eq ProductType.all.where(payupfront: true).to_sql
    end

    it 'offers retrieving only paywall ProductTypes' do
      expect(ProductType.paywall.to_sql).to eq ProductType.all.where(paywall: true).to_sql
    end

    it 'offers retrieving only tiers ProductTypes' do
      expect(ProductType.tiers.to_sql).to eq ProductType.all.where(tiers: true).order(order: :asc).to_sql
    end
  end

  describe 'validation' do
    describe 'subscription_period_type' do
      it 'enforces a PeriodType enum' do
        expect {
          Fabricate(:product_type, subscription_period_type: 55)
        }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Subscription period type must be one of [ 7, 30, 60, 90, 180, 365 ] days')
      end
    end

    describe 'introductory_period_type' do
      it 'allows saving without' do
        expect {
          Fabricate(:product_type, introductory_period_type: nil)
        }.to_not raise_error
      end

      it 'enforces a PeriodType enum' do
        expect {
          Fabricate(:product_type, introductory_period_type: 55)
        }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory period type must be one of [ 7, 30, 60, 90, 180, 365 ] days')
      end
    end

    describe 'introductory_num_periods' do
      it 'only validates if introductory_period_type provided' do
        expect {
          Fabricate(:product_type, introductory_period_type: nil, introductory_num_periods: 123)
        }.to_not raise_error
      end

      describe 'for 1 week period' do
        it 'enforces must be 1-12' do
          expect {
            Fabricate(:product_type, introductory_num_periods: nil)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [1-12] for a 1 week period')
          expect {
            Fabricate(:product_type, introductory_num_periods: 13)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [1-12] for a 1 week period')
        end
      end

      describe 'for 1 month period' do
        it 'enforces must be 1-12' do
          expect {
            Fabricate(:product_type, introductory_period_type: 30, introductory_num_periods: nil)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [1-12] for a 1 month period')
          expect {
            Fabricate(:product_type, introductory_period_type: 30, introductory_num_periods: 13)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [1-12] for a 1 month period')
        end
      end

      describe 'for 2 month period' do
        it 'enforces must be 2, 4, 6, 8, 10, 12' do
          expect {
            Fabricate(:product_type, introductory_period_type: 60, introductory_num_periods: nil)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [2, 4, 6, 8, 10, 12] for a 2 month period')
          expect {
            Fabricate(:product_type, introductory_period_type: 60, introductory_num_periods: 7)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [2, 4, 6, 8, 10, 12] for a 2 month period')
        end
      end

      describe 'for 3 month period' do
        it 'enforces must be 3, 6, 9, 12' do
          expect {
            Fabricate(:product_type, introductory_period_type: 90, introductory_num_periods: nil)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [3, 6, 9, 12] for a 3 month period')
          expect {
            Fabricate(:product_type, introductory_period_type: 90, introductory_num_periods: 7)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [3, 6, 9, 12] for a 3 month period')
        end
      end

      describe 'for 6 month period' do
        it 'enforces must be 6, 12' do
          expect {
            Fabricate(:product_type, introductory_period_type: 180, introductory_num_periods: nil)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [6, 12] for a 6 month period')
          expect {
            Fabricate(:product_type, introductory_period_type: 180, introductory_num_periods: 7)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be [6, 12] for a 6 month period')
        end
      end

      describe 'for 1 year period' do
        it 'enforces must be 1' do
          expect {
            Fabricate(:product_type, introductory_period_type: 365, introductory_num_periods: nil)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be 1 for a 1 year period')
          expect {
            Fabricate(:product_type, introductory_period_type: 365, introductory_num_periods: 7)
          }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Introductory num periods must be 1 for a 1 year period')
        end
      end
    end

    describe 'payupfront_duration' do
      it 'does not enforce duration if no payupfront_price' do
        expect {
          Fabricate(:product_type, payupfront_price: nil, payupfront_duration: 987)
        }.to_not raise_error
      end

      it 'enforces must be 1, 2, 3, 6, or 12 months if payupfront_price present' do
        expect {
          Fabricate(:product_type, payupfront_price: 9.99, payupfront_duration: nil)
        }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Payupfront duration must be one of [ 1, 2, 3, 6, 12 ] months')
        expect {
          Fabricate(:product_type, payupfront_price: 9.99, payupfront_duration: 13)
        }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Payupfront duration must be one of [ 1, 2, 3, 6, 12 ] months')
        expect {
          Fabricate(:product_type, payupfront_price: 9.99, payupfront_duration: 12)
        }.to_not raise_error
      end
    end
  end
end
