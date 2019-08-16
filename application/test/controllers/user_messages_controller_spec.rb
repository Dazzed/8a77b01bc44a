# frozen_string_literal: true

require 'sidekiq/testing'

describe UserMessagesController, type: :controller do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user) }
  let(:access_token) { JsonWebToken.encode(user_id: user.id).access_token }
  let(:friend) { Fabricate(:user) }
  let(:facebook_auth) { Fabricate(:external_auth_with_facebook, user: user) }
  let(:token) { Fabricate(:token, user: user, hashed_access_token: Digest::SHA2.hexdigest(access_token), provider: 'facebook') }
  let(:headers) {
    {
      'Authorization' => "Bearer #{access_token}",
      'Provider' => 'facebook'
    }
  }

  before(:each) do
    Timecop.scale(3600) # turn seconds into hours to help testing
    user
    # override custom instance attribute that a reloaded User object will never have and is screwing up our testing
    user.is_new = false
    friend
    friend.is_new = false
    token
    facebook_auth
    allow(User).to receive(:external_id_for_token).with(access_token, 'facebook').and_return(facebook_auth.provider_id)
    request.headers.merge!(headers)
    request.accept = 'application/json'
    # set timezone to EST to faciliate comparing JSON rendered datetimes
    Time.zone = ActiveSupport::TimeZone['Eastern Time (US & Canada)']

    friendship1 = Fabricate(:friendship, user: user, friend: friend)
    friendship1a = Fabricate(:friendship, user: friend, friend: user)
  end

  after(:each) do
    Time.zone = ActiveSupport::TimeZone['UTC']
  end

  describe 'GET /users/:id/user_messages' do
    let(:user2) { Fabricate(:user) }

    describe 'hidden users' do
      describe 'current user is initiating conversation' do
        # don't name this just :post as it will collide with `post` method for Controller DSL to make a POST call
        let(:post_by_user2) { Fabricate(:post, user: user2) }
        let(:message1) { Fabricate(:user_message, user: user, recipient_user: user2, initiating_post: post_by_user2) }
        let(:message2) { Fabricate(:user_message, user: user2, recipient_user: user) }

        before(:each) do
          message1.update_attributes(read_by_recipient: true)
          message2.update_attributes(read_by_recipient: true)
        end

        it 'returns all messages when neither user is hidden' do
          get :index, { id: user.id, user_id: user2.id }
          expect(response.status).to eq 200
          rating_ids = user.liked_posts.collect(&:id)
          expect(JSON.parse(response.body)).to eq({ 'results' => [message2, message1].as_json(include: [{ virtual_product_transaction: { include: :virtual_product_type } }, { initiating_post: { include: :poll_question, rated_ids: rating_ids } }]) })
        end

        it 'returns all messages when current user is hidden' do
          user.update_attributes(hidden_reason: 'hidden user')
          get :index, { id: user.id, user_id: user2.id }
          expect(response.status).to eq 200
          rating_ids = user.liked_posts.collect(&:id)
          expect(JSON.parse(response.body)).to eq({ 'results' => [message2, message1].as_json(include: [{ virtual_product_transaction: { include: :virtual_product_type } }, { initiating_post: { include: :poll_question, rated_ids: rating_ids } }]) })
        end

        it 'returns only current user\'s messages when other user is hidden' do
          user2.update_attributes(hidden_reason: 'hidden user')
          get :index, { id: user.id, user_id: user2.id }
          expect(response.status).to eq 200
          rating_ids = user.liked_posts.collect(&:id)
          expect(JSON.parse(response.body)).to eq({ 'results' => [message1].as_json(include: [{ virtual_product_transaction: { include: :virtual_product_type } }, { initiating_post: { include: :poll_question, rated_ids: rating_ids } }]) })
        end

        it 'returns only current user\'s messages when both users are hidden' do
          user.update_attributes(hidden_reason: 'hidden user')
          user2.update_attributes(hidden_reason: 'hidden user')
          get :index, { id: user.id, user_id: user2.id }
          expect(response.status).to eq 200
          rating_ids = user.liked_posts.collect(&:id)
          expect(JSON.parse(response.body)).to eq({ 'results' => [message1].as_json(include: [{ virtual_product_transaction: { include: :virtual_product_type } }, { initiating_post: { include: :poll_question, rated_ids: rating_ids } }]) })
        end
      end
    end

    describe 'lots of messages' do
      before(:each) do
        10.times do
          Fabricate(:user_message, user: user, recipient_user: user2)
          sleep 0.1
        end
      end

      describe 'without pagination' do
        it 'returns all records' do
          get :index, { id: user.id, user_id: user2.id }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)['results'].size).to eq 10
        end

        # UserMessage model enforces this via default_scope
        it 'returns all records in descending by :created_at order' do
          get :index, { id: user.id, user_id: user2.id }
          expect(response.status).to eq 200
          results = JSON.parse(response.body)['results']
          9.times do |i|
            expect(Time.parse(results[i]['created_at']).to_i).to be > Time.parse(results[i+1]['created_at']).to_i
          end
        end
      end

      describe 'with pagination' do
        it 'returns records with additional pagination metadata' do
          offset, max = 0, 10
          get :index, { id: user.id, user_id: user2.id, offset: offset, max: max }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)['results'].size).to eq max
          expect(JSON.parse(response.body)['offset']).to eq offset
          expect(JSON.parse(response.body)['max']).to eq max
          expect(JSON.parse(response.body)['total']).to eq UserMessage.with_users(user, user2).size
        end

        # UserMessage model enforces this via default_scope
        it 'returns all records in descending by :created_at order' do
          offset, max = 0, 10
          get :index, { id: user.id, user_id: user2.id, offset: offset, max: max }
          expect(response.status).to eq 200
          results = JSON.parse(response.body)['results']
          9.times do |i|
            expect(Time.parse(results[i]['created_at']).to_i).to be > Time.parse(results[i+1]['created_at']).to_i
          end
        end

        it 'returns only max records when supplied' do
          offset, max = 0, 5
          get :index, { id: user.id, user_id: user2.id, offset: offset, max: max }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)['offset']).to eq offset
          expect(JSON.parse(response.body)['max']).to eq max
          expect(JSON.parse(response.body)['total']).to eq UserMessage.with_users(user, user2).size
          results = JSON.parse(response.body)['results']
          expect(results.size).to eq max
          4.times do |i|
            expect(Time.parse(results[i]['created_at']).to_i).to be > Time.parse(results[i+1]['created_at']).to_i
          end
        end

        it 'returns only max records when supplied with non-zero offset' do
          offset, max = 3, 4
          get :index, { id: user.id, user_id: user2.id, offset: offset, max: max }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)['offset']).to eq offset
          expect(JSON.parse(response.body)['max']).to eq max
          expect(JSON.parse(response.body)['total']).to eq UserMessage.with_users(user, user2).size
          results = JSON.parse(response.body)['results']
          expect(results.size).to eq max
          expect(results.first['id']).to eq UserMessage.with_users(user, user2)[3].id
          expect(results.last['id']).to eq UserMessage.with_users(user, user2)[6].id
          3.times do |i|
            expect(Time.parse(results[i]['created_at']).to_i).to be > Time.parse(results[i+1]['created_at']).to_i
          end
        end

        it 'returns default number of records when no max supplied' do
          offset = 0
          get :index, { id: user.id, user_id: user2.id, offset: offset }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)['offset']).to eq offset
          expect(JSON.parse(response.body)['max']).to eq 10
          expect(JSON.parse(response.body)['total']).to eq UserMessage.with_users(user, user2).size
          results = JSON.parse(response.body)['results']
          expect(results.size).to eq 10
          9.times do |i|
            expect(Time.parse(results[i]['created_at']).to_i).to be > Time.parse(results[i+1]['created_at']).to_i
          end
        end

        it 'returns first set of records when offset is zero' do
          offset, max = 0, 10
          get :index, { id: user.id, user_id: user2.id, offset: offset, max: max }
          expect(response.status).to eq 200
          results = JSON.parse(response.body)['results']
          expect(results.size).to eq max
          expect(results.first['id']).to eq UserMessage.with_users(user, user2).first.id
          9.times do |i|
            expect(Time.parse(results[i]['created_at']).to_i).to be > Time.parse(results[i+1]['created_at']).to_i
          end
        end

        it 'skips appropriate records when offset non-zero' do
          offset, max = 5, 10
          get :index, { id: user.id, user_id: user2.id, offset: offset, max: max }
          expect(response.status).to eq 200
          results = JSON.parse(response.body)['results']
          expect(results.size).to eq 5
          expect(results.first['id']).to eq UserMessage.with_users(user, user2)[5].id
          4.times do |i|
            expect(Time.parse(results[i]['created_at']).to_i).to be > Time.parse(results[i+1]['created_at']).to_i
          end
        end
      end
    end
  end

  describe 'POST /posts/:id/user_messages' do
    let(:user2) { Fabricate(:user) }
    # don't name this just :post as it will collide with `post` method for Controller DSL to make a POST call
    let(:post_by_user2) { Fabricate(:post, user: user2) }

    describe 'hidden user' do
      before(:each) do
        user.update_attribute(:hidden_reason, 'hide this user')
      end

      describe 'with text reply' do
        before(:each) do
          # turn off Obscenity filter
          allow(Obscenity).to receive(:profane?).and_return(false)
        end

        it 'does not send SNS notification after replying to another user\'s post' do
          expect_any_instance_of(Aws::SNS::Client).to_not receive(:publish)
          post :create, { post_id: post_by_user2.id, user_message: { text: 'Hello' } }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)).to eq UserMessage.first.as_json(:include => [:recipient_user, :conversation])
        end
      end
    end

    describe 'blocked by recipient user' do
      before(:each) do
        block = Fabricate(:user_block, user: user2, blocked_user_id: user.id)
      end

      describe 'with text reply' do
        before(:each) do
          # turn off Obscenity filter
          allow(Obscenity).to receive(:profane?).and_return(false)
        end

        it 'returns 404 if replying to a user post' do
          post :create, { post_id: post_by_user2.id, user_message: { text: 'Hello' } }
          expect(response.status).to eq 404
        end

        it 'returns 404 if replying to a direct message' do
          user.user_settings.update_attribute :pro_subscription_expiration, Time.now+1.day
          post :create, { post_id: post_by_user2.id, user_message: { text: 'Hello' } }
          expect(response.status).to eq 404
        end
      end
    end

    describe 'visible user' do
      before(:each) do
        allow_any_instance_of(Aws::SNS::Client).to receive(:publish).and_return(true)
      end

      describe 'params validation' do
        it 'responds with 404 for user_id not found' do
          post :create, { user_id: 999_999, user_message: { text: 'Hello' } }
          expect(response.status).to eq 404
          expect(response.body).to eq({ error: 'This user has removed their account' }.to_json)
        end

        it 'responds with 404 for post_id not found' do
          post :create, { post_id: 999_999, user_message: { text: 'Hello' } }
          expect(response.status).to eq 404
          expect(response.body).to eq({ error: 'This post has been removed' }.to_json)
        end
      end

      describe 'with text reply' do
        before(:each) do
          # turn off Obscenity filter
          allow(Obscenity).to receive(:profane?).and_return(false)
        end

        it 'allows replying again to the same Post with different text' do
          post_by_user2 = Fabricate(:post, user: user2)
          # first reply message
          Fabricate(:user_message, user: user, recipient_user: user2, initiating_post: post_by_user2)
          post :create, { post_id: post_by_user2.id, user_message: { text: 'Hello' } }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)).to eq UserMessage.first.as_json(:include => [:recipient_user, :conversation])
        end

        it 'does not allow replying again to the same Post with the same text but fails silently' do
          post_by_user2 = Fabricate(:post, user: user2)
          # first reply message
          message = Fabricate(:user_message, user: user, recipient_user: user2, initiating_post: post_by_user2)
          post :create, { post_id: post_by_user2.id, user_message: { text: message.text } }
          expect(response.status).to eq 200
          expect(response.body).to eq({ error: 'You have already responded to this post' }.to_json)
        end

        it 'does not allow replying again to the same Post with the same text but fails silently when initial validation didn\'t catch it due to simultaneous requests' do
          post_by_user2 = Fabricate(:post, user: user2)
          # first reply message
          message = Fabricate(:user_message, user: user, recipient_user: user2, initiating_post: post_by_user2)
          allow(UserMessage).to receive(:find_by).with(user: user, initiating_post: post_by_user2, text: message.text, external_image_url: message.external_image_url).and_return(false)
          post :create, { post_id: post_by_user2.id, user_message: { text: message.text } }
          expect(response.status).to eq 200
          expect(response.body).to eq({ result: 'You have already responded to this post' }.to_json)
        end

        it 'allows replying to another user\'s post' do
          post :create, { post_id: post_by_user2.id, user_message: { text: 'Hello' } }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)).to eq UserMessage.first.as_json(:include => [:recipient_user, :conversation])
        end

        it 'constructs SendAPNJob with correct params' do
          text = "Hello"
          assert_enqueued_with(
            job: SendAPNJob,
            args: [
              [user2.id],
              {
                type: 'new_message',
                route: {
                  link: 'conversation',
                  objectId: "#{user.id}"
                },
                title: "#{user.first_name}: #{text}",
                toaster_body: "#{user.first_name}: #{text}",
                user_first_name: "#{user.first_name}",
                user_profile_image_url: user.profile_photo
              }
            ]
          ) do
            post :create, { post_id: post_by_user2.id, user_message: { text: 'Hello' } }
            expect(response.status).to eq 200
            expect(JSON.parse(response.body)).to eq UserMessage.first.as_json(include: [:recipient_user, :conversation])
          end
        end

        describe 'and target user has turned off new_post_reply_push' do
          before(:each) do
            user2.user_settings.update_attributes(new_post_reply_push: false)
          end
        end
      end

      describe 'with image reply' do
        let(:image) { 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAABJ0AAASdAHeZh94AAAAB3RJTUUH4wMUCykN8n11IwAAAB9JREFUGNNjPHToEAMxgImBSECSQkZiFf4fODcOkEIAo5MDWpJzPWAAAAAASUVORK5CYII=' }

        before(:each) do
          # allow(Base64).to receive(:decode64).and_return(true)
          allow(ActionDispatch::Http::UploadedFile).to receive(:initialize).and_return(image)
          allow_any_instance_of(UserMessage).to receive(:store_image!).and_return(true)
        end

        describe 'to a Post' do
          it 'does not allow replying to another user\'s post if no existing Conversation' do
            post :create, { post_id: post_by_user2.id, user_message: { text: nil, base64_image: image } }
            expect(response.status).to eq 403
            expect(response.body).to eq({ error: 'Sorry, you must wait for a reply before sending an image..', message: 'Sorry, you must wait for a reply before sending an image..' }.to_json)
          end

          it 'does not allow replying to another user\'s post if no mutual Conversation' do
            # first message from User1 to User2 is a simple message
            user_message1 = Fabricate(:user_message, user: user, recipient_user: user2)
            # first message by User2 is a post reply to User1's Post
            post_by_user1 = Fabricate(:post, user: user)
            user_message2 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post_by_user1)
            # User2 has never sent a regular message so the Conversation is not mutual and image upload by User1 for User2's Post should not be allowed...
            post :create, { post_id: post_by_user2.id, user_message: { text: nil, base64_image: image } }
            expect(response.status).to eq 403
            expect(response.body).to eq({ error: 'Sorry, you must wait for a reply before sending an image..', message: 'Sorry, you must wait for a reply before sending an image..' }.to_json)
          end

          it 'allows replying to another user\'s post if there is a mutual Conversation' do
            # first message from User1 to User2 is a simple message
            user_message1 = Fabricate(:user_message, user: user, recipient_user: user2)
            # first message by User2 to User1 is a simple message
            user_message2 = Fabricate(:user_message, user: user2, recipient_user: user)
            # without a post reply this Conversation should be mutual...
            post :create, { post_id: post_by_user2.id, user_message: { text: nil, base64_image: image } }
            expect(response.status).to eq 200
            expect(JSON.parse(response.body)).to eq UserMessage.all.first.as_json(:include => [:recipient_user, :conversation]).merge('image_url' => JSON.parse(response.body)['image_url'])
          end
        end

        describe 'to a direct message' do
          it 'does not allow replying if no existing Conversation' do
            post :create, { user_id: user2.id, user_message: { text: nil, base64_image: image } }
            expect(response.status).to eq 403
            expect(response.body).to eq({ error: 'Sorry, you must wait for a reply before sending an image..', message: 'Sorry, you must wait for a reply before sending an image..' }.to_json)
          end

          it 'does not allow replying if no mutual Conversation' do
            # first message from User1 to User2 is a simple message
            user_message1 = Fabricate(:user_message, user: user, recipient_user: user2)
            # User2 has never sent a regular message so the Conversation is not mutual and image upload by User1 for User2 should not be allowed...
            post :create, { user_id: user2.id, user_message: { text: nil, base64_image: image } }
            expect(response.status).to eq 403
            expect(response.body).to eq({ error: 'Sorry, you must wait for a reply before sending an image..', message: 'Sorry, you must wait for a reply before sending an image..' }.to_json)
          end

          it 'does not allow replying if there is a mutual Conversation but not a Pro subscriber' do
            # first message from User1 to User2 is a simple message
            user_message1 = Fabricate(:user_message, user: user, recipient_user: user2)
            # first message by User2 to User1 is a simple message
            user_message2 = Fabricate(:user_message, user: user2, recipient_user: user)
            # this Conversation should be mutual...
            post :create, { user_id: user2.id, user_message: { text: nil, base64_image: image } }
            expect(response.status).to eq 403
            expect(response.body).to eq({ error: 'You must subscribe to start new direct message conversations.', message: 'You must subscribe to start new direct message conversations.' }.to_json)
          end

          it 'allows replying if there is a mutual Conversation, active Conversation - Pro subscriber to Basic' do
            # make User1 a Pro user...
            user.user_settings.update_attributes(pro_subscription_expiration: Time.current + 24.hours)
            # first message from User1 to User2 is a simple message
            user_message1 = Fabricate(:user_message, user: user, recipient_user: user2)
            # first message by User2 to User1 is a simple message
            user_message2 = Fabricate(:user_message, user: user2, recipient_user: user)
            # second message by User2 is a post reply to User1's Post
            post_by_user1 = Fabricate(:post, user: user)
            user_message3 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post_by_user1)
            # this Conversation should be mutual, active, and allowed by Pro status...
            post :create, { user_id: user2.id, user_message: { text: nil, base64_image: image } }
            expect(response.status).to eq 200
            expect(JSON.parse(response.body)).to eq UserMessage.all.first.as_json(:include => [:recipient_user, :conversation]).merge('image_url' => JSON.parse(response.body)['image_url'])
          end

          it 'allows replying if there is a mutual Conversation, active Conversation - Basic to Pro subscriber' do
            # make User2 a Pro user...
            user2.user_settings.update_attributes(pro_subscription_expiration: Time.current + 24.hours)
            # first message from User1 to User2 is a simple message
            user_message1 = Fabricate(:user_message, user: user, recipient_user: user2)
            # first message by User2 to User1 is a simple message
            user_message2 = Fabricate(:user_message, user: user2, recipient_user: user)
            # second message by User2 is a post reply to User1's Post
            post_by_user1 = Fabricate(:post, user: user)
            user_message3 = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post_by_user1)
            # this Conversation should be mutual, active, and allowed by Pro status...
            post :create, { user_id: user2.id, user_message: { text: nil, base64_image: image } }

            expect(response.status).to eq 200
            expect(JSON.parse(response.body)).to eq UserMessage.all.first.as_json(:include => [:recipient_user, :conversation]).merge('image_url' => JSON.parse(response.body)['image_url'])
          end
        end
      end
    end

    describe 'friend' do
      before(:each) do
        allow_any_instance_of(Aws::SNS::Client).to receive(:publish).and_return(true)
      end

      describe 'with text reply' do
        it 'allows replying a friend story if a friend' do
          friend_story = Fabricate(:friend_story, user: friend)

          post :create, {user_id: friend.id,  user_message: { text: 'Hello', friend_story_id: friend_story.id } }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)).to eq UserMessage.first.as_json(:include => [:recipient_user, :conversation, :friend_story])
        end

        it 'allows replying multiple times to friend story if a friend' do
          friend_story = Fabricate(:friend_story, user: friend)

          post :create, {user_id: friend.id,  user_message: { text: 'Hello', friend_story_id: friend_story.id } }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)).to eq UserMessage.first.as_json(:include => [:recipient_user, :conversation, :friend_story])

          post :create, {user_id: friend.id,  user_message: { text: 'Hello', friend_story_id: friend_story.id } }
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)).to eq UserMessage.first.as_json(:include => [:recipient_user, :conversation, :friend_story])
        end

        it 'does not allow replying to a friend story if not a friend' do
          friend_story = Fabricate(:friend_story, user: user2)

          post :create, { user_id: user2.id, user_message: { text: 'Hello', friend_story_id: friend_story.id } }
          expect(response.status).to eq 403
        end

        describe 'to a direct message' do
          it 'it allow replying if no existing Conversation' do
            post :create, { user_id: friend.id, user_message: { text: "Hello",  } }
            expect(response.status).to eq 200
            expect(JSON.parse(response.body)).to eq UserMessage.first.as_json(:include => [:recipient_user, :conversation, :friend_story])
          end
        end
      end
    end
  end

  describe 'GET /users/:id/user_messages/new_messages' do
    let(:user2) { Fabricate(:user) }

    it 'returns new messages if both users are not hidden' do
      # we message first, to make a conversation
      Fabricate(:user_message, user: user, recipient_user: user2)
      # reply by User2 to User1
      user_message2 = Fabricate(:user_message, user: user2, recipient_user: user)
      get :new_messages, { user_id: user2.id }
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({ 'results' => [user_message2].as_json(include: { virtual_product_transaction: { include: :virtual_product_type } }), 'is_typing' => false })
    end

    it 'returns new messages if current user is hidden' do
      # we message first, to make a conversation
      Fabricate(:user_message, user: user, recipient_user: user2)
      # reply by User2 to User1
      user_message2 = Fabricate(:user_message, user: user2, recipient_user: user)
      user.update_attributes(hidden_reason: 'hidden user')
      get :new_messages, { user_id: user2.id }
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({ 'results' => [user_message2].as_json(include: { virtual_product_transaction: { include: :virtual_product_type } }), 'is_typing' => false })
    end

    it 'does not return new messages if other user is hidden' do
      # we message first, to make a conversation
      Fabricate(:user_message, user: user, recipient_user: user2)
      # reply by User2 to User1
      user_message2 = Fabricate(:user_message, user: user2, recipient_user: user)
      user2.update_attributes(hidden_reason: 'hidden user')
      get :new_messages, { user_id: user2.id }
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({ 'results' => [], 'is_typing' => false })
    end
  end
end
