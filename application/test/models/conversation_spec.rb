# frozen_string_literal: true

describe Conversation do
  let(:user) { Fabricate(:user) }

  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :initiating_user_id }
    it { expect(subject).to have_db_column :target_user_id }
    it { expect(subject).to have_db_column :initiating_message_id }
    it { expect(subject).to have_db_column :initiating_user_typing }
    it { expect(subject).to have_db_column :target_user_typing }
    it { expect(subject).to have_db_column :most_recent_message_id }
    it { expect(subject).to have_db_column :can_initiating_user_reply }
    it { expect(subject).to have_db_column :can_target_user_reply }
    it { expect(subject).to have_db_column :count_towards_message_restriction }
    it { expect(subject).to have_db_column :starred_by_posting_user }
    it { expect(subject).to have_db_column :is_active }
    it { expect(subject).to have_db_column :hidden_by_target_user }
    it { expect(subject).to have_db_column :hidden_by_initiating_user }
    it { expect(subject).to have_db_column :target_user_unread_messages }
    it { expect(subject).to have_db_column :initiating_user_unread_messages }
    it { expect(subject).to have_db_column :expires_at }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:initiating_user) }
    it { expect(subject).to belong_to(:target_user) }
    it { expect(subject).to belong_to(:initiating_message) }
    it { expect(subject).to belong_to(:most_recent_message) }
    it { expect(subject).to have_many(:user_messages) }
    it { expect(subject).to have_many(:posts) }
    it { expect(subject).to have_many(:ratings) }
    it { expect(subject).to have_many(:positive_ratings) }
    it { expect(subject).to have_many(:negative_ratings) }
  end

  describe 'scopes' do
    it 'offers retrieving only Conversations with initiating users that are not hidden' do
      expect(Conversation.user_visible.to_sql).to eql Conversation.joins('LEFT JOIN users AS initiating_users ON initiating_users.id = conversations.initiating_user_id').where("initiating_users.hidden_reason IS NULL or initiating_users.hidden_reason = ''").to_sql
    end

    it 'offers retrieving only Conversations with target users that are not hidden' do
      expect(Conversation.target_user_visible.to_sql).to eql Conversation.joins('LEFT JOIN users AS target_users ON target_users.id = conversations.target_user_id').where("target_users.hidden_reason IS NULL or target_users.hidden_reason = ''").to_sql
    end
  end

  describe 'active_conversation_with_users' do
    it 'returns first active Conversation between 2 users no matter what order you ask' do
      # first Post and Message
      post1 = Fabricate(:post, user: user)
      user2 = Fabricate(:user)
      message1 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post1)
      # first Conversation is NOT active
      message1.conversation.update_attribute(:is_active, false)
      # second Post and Message
      post2 = Fabricate(:post, user: user)
      message2 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post2)
      # second Conversation is active
      message2.conversation.update_attribute(:is_active, true)
      expect(Conversation.active_conversation_with_users(user, user2)).to eq message2.conversation
      expect(Conversation.active_conversation_with_users(user2, user)).to eq message2.conversation
    end

    it 'returns first unexpired Conversation between 2 users if none active no matter what order you ask' do
      # first Post and Message
      post1 = Fabricate(:post, user: user)
      user2 = Fabricate(:user)
      message1 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post1)
      # first Conversation is NOT active
      message1.conversation.update_attribute(:is_active, false)
      # first Message is over a day old
      message1.update_attribute(:created_at, 2.days.ago)
      # second Post and Message
      post2 = Fabricate(:post, user: user)
      message2 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post2)
      # second Conversation is NOT active
      message2.conversation.update_attribute(:is_active, false)
      expect(Conversation.active_conversation_with_users(user, user2)).to eq message2.conversation
      expect(Conversation.active_conversation_with_users(user2, user)).to eq message2.conversation
    end

    it 'returns nothing if no active or unexpired Conversations' do
      # first Post and Message
      post1 = Fabricate(:post, user: user)
      user2 = Fabricate(:user)
      message1 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post1)
      # first Conversation is NOT active
      message1.conversation.update_attribute(:is_active, false)
      # first Message is over a day old
      message1.update_attribute(:created_at, 2.days.ago)
      # second Post and Message
      post2 = Fabricate(:post, user: user)
      message2 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post2)
      # second Conversation is NOT active
      message2.conversation.update_attribute(:is_active, false)
      # second Message is over a day old
      message2.update_attribute(:created_at, 2.days.ago)
      expect(Conversation.active_conversation_with_users(user, user2)).to eq nil
      expect(Conversation.active_conversation_with_users(user2, user)).to eq nil
    end
  end
end
