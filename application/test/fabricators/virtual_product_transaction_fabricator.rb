# frozen_string_literal: true

Fabricator(:virtual_product_transaction) do
  # user_id nil
  # recipient_user_id nil
  # virtual_product_type_id
  user_message nil
  total_award_amount 0
  total_cost 0
  redemption_date nil
  purchase_receipt_id nil
  quantity 1
end
