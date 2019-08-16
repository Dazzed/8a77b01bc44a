# frozen_string_literal: true

Fabricator(:purchase_receipt_data) do
  base64_data  { Base64.encode64(Faker::Lorem.paragraph(10)) }
end

