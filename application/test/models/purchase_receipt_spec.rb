# frozen_string_literal: true

describe PurchaseReceipt do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :transaction_id }
    it { expect(subject).to have_db_column :quantity }
    it { expect(subject).to have_db_column :product_id }
    it { expect(subject).to have_db_column :original_transaction_id }
    it { expect(subject).to have_db_column :purchase_date }
    it { expect(subject).to have_db_column :original_purchase_date }
    it { expect(subject).to have_db_column :expires_date }
    it { expect(subject).to have_db_column :web_order_line_item_id }
    it { expect(subject).to have_db_column :is_trial_period }
    it { expect(subject).to have_db_column :is_in_intro_offer_period }
    it { expect(subject).to have_db_column :internal_status }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:user) }
    it { expect(subject).to belong_to(:purchase_receipt_data) }
    it { expect(subject).to have_one(:virtual_product_transaction) }
    it { expect(subject).to have_one(:user_settings) }
  end

  before(:each) do
    stub_request(:put, /foundermark-friended-dev.s3.amazonaws.com/)
      .to_return(status: 200, body: "stubbed response", headers:{"Etag": nil})
  end

  describe 'initial?' do
    it 'reports true for a brand new instance' do
      instance = Fabricate(:purchase_receipt)
      expect(instance.initial?).to be true
    end

    it 'reports false for a processed instance' do
      instance = Fabricate(:purchase_receipt, internal_status: PurchaseReceipt::STATUS_PROCESSED)
      expect(instance.initial?).to be false
    end
  end

  describe 'class methods' do
    let(:user) { Fabricate(:user) }
    let(:sample_payload) do
      payload = JSON.parse(File.read(Rails.root.join('spec/fixtures/sample_receipt.json')))
      payload.deep_symbolize_keys!
    end
    let(:price) { 12.99 }

    describe 'store_receipts!' do
      it 'creates a PurchaseReceipt for each receipt in array of receipts' do
        PurchaseReceipt.store_receipts!(user, sample_payload, price)
        expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
        expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['310000293756518', '70000458734964']
        expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [true, true]
        expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
      end

      describe 'only one receipt in :latest_receipt_info' do
        let(:sample_payload) do
          payload = JSON.parse(File.read(Rails.root.join('spec/fixtures/sample_receipt_one_latest_receipt.json')))
          payload.deep_symbolize_keys!
        end

        it 'creates a PurchaseReceipt' do
          PurchaseReceipt.store_receipts!(user, sample_payload, price)
          expect(PurchaseReceipt.all.map(&:quantity)).to eq [1]
          expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['310000293756518']
          expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [true]
          expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt]]
        end
      end

      describe 'recording price' do
        before(:each) do
          # fabricates with price of 9.99
          Fabricate(:product_type, apple_product_id: sample_payload[:latest_receipt_info].first[:product_id])
        end

        it 'uses ProductType price for product in receipt if lower than (or equal to) client provided price' do
          PurchaseReceipt.store_receipts!(user, sample_payload, price)
          expect(PurchaseReceipt.all.map(&:price)).to eq [9.99, 9.99]
        end

        it 'uses ProductType price for product in receipt if higher than client provided price and user has consented to price increase' do
          sample_payload[:pending_renewal_info] = [
            {
              "expiration_intent": "1",
              "auto_renew_product_id": "com.foundermark.Friended.prosub",
              "original_transaction_id": "1000000383872448",
              "is_in_billing_retry_period": "0",
              "product_id": "com.foundermark.Friended.prosub",
              "auto_renew_status": "0",
              "price_consent_status": "1"
            },
            {
              "expiration_intent": "1",
              "auto_renew_product_id": "com.foundermark.Friended.prosub",
              "original_transaction_id": "70000458734964",
              "is_in_billing_retry_period": "0",
              "product_id": "com.foundermark.Friended.prosub",
              "auto_renew_status": "0",
              "price_consent_status": "1"
            }
          ]
          PurchaseReceipt.store_receipts!(user, sample_payload, 4.99)
          expect(PurchaseReceipt.all.map(&:price)).to eq [9.99, 9.99]
        end

        it 'uses client provided price if ProductType price for product in receipt is higher than client provided price and user has NOT consented to price increase' do
          sample_payload[:pending_renewal_info] = [
            {
              "expiration_intent": "1",
              "auto_renew_product_id": "com.foundermark.Friended.prosub",
              "original_transaction_id": "1000000383872448",
              "is_in_billing_retry_period": "0",
              "product_id": "com.foundermark.Friended.prosub",
              "auto_renew_status": "0",
              "price_consent_status": "0"
            },
            {
              "expiration_intent": "1",
              "auto_renew_product_id": "com.foundermark.Friended.prosub",
              "original_transaction_id": "70000458734964",
              "is_in_billing_retry_period": "0",
              "product_id": "com.foundermark.Friended.prosub",
              "auto_renew_status": "0",
              "price_consent_status": "0"
            }
          ]
          PurchaseReceipt.store_receipts!(user, sample_payload, 4.99)
          expect(PurchaseReceipt.all.map(&:price)).to eq [4.99, 4.99]
        end
      end
    end

    describe 'mark_receipts_processed!' do
      it 'sets internal_status to processed for all receipts' do
        PurchaseReceipt.store_receipts!(user, sample_payload, price)
        expect(PurchaseReceipt.all.map(&:internal_status)).to eq [PurchaseReceipt::STATUS_INITIAL, PurchaseReceipt::STATUS_INITIAL]
        expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
        PurchaseReceipt.mark_receipts_processed!(sample_payload[:latest_receipt_info])
        expect(PurchaseReceipt.all.map(&:internal_status)).to eq [PurchaseReceipt::STATUS_PROCESSED, PurchaseReceipt::STATUS_PROCESSED]
      end
    end
  end
end
