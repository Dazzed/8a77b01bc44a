# frozen_string_literal: true

Fabricator(:user_message) do
  # user_id  nil
  # recipient_user_id  nil
  text { Faker::Lorem.paragraph(10)[0..190] }
  after_build do |user_message|
    conversation = Conversation.for_users(user_message.user.id, user_message.recipient_user.id)
    user_message.conversation = conversation || Conversation.create!(initiating_user: user_message.user, target_user: user_message.recipient_user)
    user_message.conversation.update_attribute :most_recent_message_id, user_message.id
  end
end
