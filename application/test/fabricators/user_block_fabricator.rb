# frozen_string_literal: true

Fabricator(:user_block) do
  # user_id
  # blocked_user_id
  block_flag { Enums::UserBlockFlags.ids.sample }
  reason_text { Faker::Lorem.sentence }
end
