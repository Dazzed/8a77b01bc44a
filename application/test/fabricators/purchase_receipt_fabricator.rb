# frozen_string_literal: true

Fabricator(:purchase_receipt) do
  # user_id  nil
  transaction_id { Faker::Crypto.md5 }
  product_id { IN_APP_PURCHASE_PRODUCTS[IN_APP_PURCHASE_PRODUCTS.keys.sample] }
end

Fabricator(:purchase_receipt_with_receipt_data, from: :purchase_receipt) do
  after_create do |pr|
    pr.purchase_receipt_data = Fabricate(:purchase_receipt_data)
    pr.save!
  end
end
