# frozen_string_literal: true

describe UserMessage do
  let(:user) { Fabricate(:user) }
  let(:user2) { Fabricate(:user) }
  subject { Fabricate(:user_message, user: user, recipient_user: user2) }

  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :recipient_user_id }
    it { expect(subject).to have_db_column :text }
    it { expect(subject).to have_db_column :emphasis_level }
    it { expect(subject).to have_db_column :conversation_id }
    it { expect(subject).to have_db_column :read_by_recipient }
    it { expect(subject).to have_db_column :image }
    it { expect(subject).to have_db_column :external_image_url }
    it { expect(subject).to have_db_column :image_auto_deleted }
    it { expect(subject).to have_db_column :deleted }
    it { expect(subject).to have_db_column :recipient_reminder_sent_at }
    it { expect(subject).to have_db_column :initiating_post_id }
    it { expect(subject).to have_db_column :recipient_rating_value }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
    it { expect(subject).to have_db_column :guess_game_id }
    it { expect(subject).to have_db_column :virtual_product_transaction_id }
    it { expect(subject).to have_db_column :friend_story_id }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:user) }
    it { expect(subject).to belong_to(:recipient_user) }
    it { expect(subject).to belong_to(:conversation) }
    it { expect(subject).to belong_to(:initiating_post) }
    it { expect(subject).to belong_to(:virtual_product_transaction) }
    it { expect(subject).to belong_to(:game) }
  end

  describe 'scopes' do
    it 'offers only retrieving recent posts' do
      now = Time.current
      Timecop.freeze(now) do
        expect(UserMessage.recent.to_sql).to eq UserMessage.all.where('user_messages.created_at > ?', now - CONSTANTS[:posts_feed_timebox_hours].hours).to_sql
      end
    end

    it 'offers only retrieving messages where user is not hidden' do
      expect(UserMessage.user_visible.to_sql).to eq UserMessage.joins(:user).where("users.hidden_reason IS NULL or users.hidden_reason = ''").to_sql
    end

    it 'offers only retrieving messages where recipient user is not hidden' do
      expect(UserMessage.recipient_user_visible.to_sql).to eq UserMessage.joins(:recipient_user).where("recipient_users_user_messages.hidden_reason IS NULL or recipient_users_user_messages.hidden_reason = ''").to_sql
    end
  end

  describe 'validations' do
    it 'does not allow same UserMessage :text for the same Post' do
      post = Fabricate(:post, user: user2)
      subject.initiating_post = post
      subject.save!
      new_message = Fabricate.build(:user_message, user: user, recipient_user: user2, initiating_post: post, text: subject.text)
      expect { new_message.save! }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Text has already been taken')
    end

    it 'allows same UserMessage :text for a different Post' do
      post = Fabricate(:post, user: user2)
      subject.initiating_post = post
      subject.save!
      post2 = Fabricate(:post, user: user2)
      new_message = Fabricate.build(:user_message, user: user, recipient_user: user2, initiating_post: post2, text: subject.text)
      expect { new_message.save! }.to_not raise_error
    end

    it 'allows same UserMessage :text when no Post' do
      post = Fabricate(:post, user: user2)
      subject.initiating_post = post
      subject.save!
      new_message = Fabricate.build(:user_message, user: user, recipient_user: user2, initiating_post: nil, text: subject.text)
      expect { new_message.save! }.to_not raise_error
    end
  end

  describe 'post_id' do
    let(:post) { Fabricate(:post, user: user) }

    before(:each) do
      subject.update_attributes!(initiating_post: post)
    end

    it 'responds with id of associated post' do
      expect(subject.post_id).to eq post.id
    end
  end

  describe 'with_users' do
    it 'retrieves all messages between 2 users' do
      post = Fabricate(:post, user: user2)
      subject.initiating_post = post
      subject.save!
      expect(UserMessage.with_users(user, user2)).to eq [subject]
    end

    it 'retrieves all messages if target user is hidden' do
      post = Fabricate(:post, user: user2)
      subject.initiating_post = post
      subject.save!
      user2.update_attribute(:hidden_reason, 'hidden user')
      expect(UserMessage.with_users(user, user2)).to eq [subject]
    end

    it 'retrieves all messages if source user is hidden' do
      post = Fabricate(:post, user: user2)
      subject.initiating_post = post
      subject.save!
      user.update_attribute(:hidden_reason, 'hidden user')
      expect(UserMessage.with_users(user, user2)).to eq [subject]
    end
  end
end
