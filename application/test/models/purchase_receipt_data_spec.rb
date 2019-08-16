# frozen_string_literal: true

describe PurchaseReceiptData do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :base64_data }
    it { expect(subject).to have_db_column :base64_data_file }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to have_one(:purchase_receipt) }
  end


  # !TODO: This is not a good test for verifying that receipts are stored in s3
  it 'stores big receipt data in s3 and not in the database' do
    payload = JSON.parse(File.read(Rails.root.join('spec/fixtures/sample_big_receipt_to_verify.json')))
    receipt = payload["receipt"]

    stub_request(:put, /foundermark-friended-dev.s3.amazonaws.com/)
      .to_return(status: 200, body: receipt, headers:{"Etag": nil})

    expect_any_instance_of(PurchaseReceiptData).to receive(:store)
    purchase_receipt_data = PurchaseReceiptData.find_by_or_create(receipt)
  end
end
