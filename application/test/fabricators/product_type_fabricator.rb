# frozen_string_literal: true

Fabricator(:product_type) do
  name { sequence(:product_type_name) { |i| "Product Type #{i}" } }
  description { Faker::Lorem.paragraph(10) }
  apple_product_id { sequence(:product_type_apple_product_id) { |i| "com.foundermark.Friended.product_type_#{i}" } }
  subscription_price { 9.99 }
  subscription_period_type { 7 }
  introductory_price { 9.99 }
  introductory_period_type { 7 }
  introductory_num_periods { 1 }
  payupfront_price { 19.99 }
  payupfront_duration { 6 }
  enabled { true }
  order { sequence(:product_type_order) { |i| i } }
  badge_text { Faker::Lorem.sentence }
end

Fabricator(:pro_subscription_product, from: :product_type) do
  apple_product_id { 'com.foundermark.Friended.prosub' }
end

Fabricator(:virtual_currency_small_product, from: :product_type) do
  apple_product_id { 'com.foundermark.Friended.virtual_currency_purchase_small' }
end
