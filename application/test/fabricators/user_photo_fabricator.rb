# frozen_string_literal: true

Fabricator(:user_photo) do
  # user_id
  external_image_url { Faker::Avatar.image }
end
