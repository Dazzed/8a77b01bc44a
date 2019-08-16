# frozen_string_literal: true

Fabricator(:external_auth_with_facebook, class_name: 'ExternalAuthProvider') do
  # user_id nil
  provider_id { Faker::Crypto.md5 }
  provider_type 'facebook'
end
