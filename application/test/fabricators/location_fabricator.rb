# frozen_string_literal: true

Fabricator(:location) do
  city { Faker::Address.city }
  state_province { Faker::Address.state }
  postal_code { Faker::Address.postcode }
  country { Faker::Address.country }
  country_code { Faker::Address.country_code }
  latitude { Faker::Address.latitude.to_f.round(4) }
  longitude { Faker::Address.longitude.to_f.round(4) }
end

Fabricator(:san_francisco, class_name: 'Location') do
  city 'San Francisco'
  state_province 'California'
  postal_code '94108'
  country 'United States'
  country_code 'US'
  latitude '37.7858'
  longitude '-122.406'
end

Fabricator(:san_francisco_short_CA, from: :san_francisco) do
  state_province 'CA'
end
