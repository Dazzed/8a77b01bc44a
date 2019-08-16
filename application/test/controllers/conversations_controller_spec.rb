# frozen_string_literal: true

describe ConversationsController, type: :controller do
  let(:user) { Fabricate(:user) }
  let(:access_token) { JsonWebToken.encode(user_id: user.id).access_token }
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
    token
    facebook_auth
    allow(ExternalAuthProvider).to receive(:external_id_for_token).with(access_token, 'facebook').and_return(facebook_auth.provider_id)
    request.headers.merge!(headers)
    request.accept = 'application/json'
  end

  describe 'GET /users/:user_id/conversations/by_user' do
    let(:user2) { Fabricate(:user) }

    describe 'current user is initiating conversation' do
      # don't name this just :post as it will collide with `post` method for Controller DSL to make a POST call
      let(:post_by_user2) { Fabricate(:post, user: user2) }

      before(:each) do
        # initiate a Conversation by replying to a Post...
        message = Fabricate(:user_message, user: user, recipient_user: user2, initiating_post: post_by_user2)
        # set it active and expire in the future...
        message.conversation.update_attributes(is_active: true, expires_at: Time.current + 1.day)
        expect(Conversation.where(initiating_user_id: user.id).length).to eq 1
      end

      it 'shows conversation when neither user is hidden' do
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => Conversation.where(initiating_user_id: user.id).as_json(include:  :most_recent_message, current_user: user, rating_count_for_user: user, unread_count_for_user_id: user.id) })
      end

      it 'hides conversation when target user is hidden' do
        user2.update_attributes(hidden_reason: 'hidden user')
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => [] })
      end

      it 'hides conversation when current/initiating user hides the conversation' do
        conversation = Conversation.for_users(user.id, user2.id)
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)["results"].map{|r| r["id"]}).to eq([conversation.id])
        put :hide, {withUserId: user2.id}
        expect(response.status).to eq 200
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)["results"].map{|r| r["id"]}).to eq([])
      end

      it 'shows conversation when current user is hidden' do
        user.update_attributes(hidden_reason: 'hidden user')
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => Conversation.where(initiating_user_id: user.id).as_json(include:  :most_recent_message, current_user: user, rating_count_for_user: user, unread_count_for_user_id: user.id) })
      end

      it 'hides conversation when both users are hidden' do
        user.update_attributes(hidden_reason: 'hidden user')
        user2.update_attributes(hidden_reason: 'hidden user')
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => [] })
      end

      it 'excludes friend conversations' do
        friendship = Fabricate(:friendship, user: user, friend: user2)
        friendship_inverse = Fabricate(:friendship, user: user2, friend: user)
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)['results'].length).to eq(0)
      end
    end

    describe 'current user is target of conversation' do
      # don't name this just :post as it will collide with `post` method for Controller DSL to make a POST call
      let(:post_by_user) { Fabricate(:post, user: user) }

      before(:each) do
        # initiate a Conversation by replying to a Post...
        message = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post_by_user)
        # set it active and expire in the future...
        message.conversation.update_attributes(is_active: true, expires_at: Time.current + 1.day)
        expect(Conversation.where(target_user_id: user.id).length).to eq 1
      end

      it 'excludes friend conversations' do
        friendship = Fabricate(:friendship, user: user, friend: user2)
        friendship_inverse = Fabricate(:friendship, user: user2, friend: user)
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)['results'].length).to eq(0)
      end

      it 'shows conversation when neither user is hidden' do
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => Conversation.where(target_user_id: user.id).as_json(include:  :most_recent_message, current_user: user, rating_count_for_user: user, unread_count_for_user_id: user.id) })
      end

      it 'hides conversation when initiating user is hidden' do
        user2.update_attributes(hidden_reason: 'hidden user')
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => [] })
      end

      it 'hides conversation when current/target user hides the conversation' do
        conversation = Conversation.for_users(user.id, user2.id)
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)["results"].map{|r| r["id"]}).to eq([conversation.id])
        put :hide, {withUserId: user2.id}
        expect(response.status).to eq 200
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)["results"].map{|r| r["id"]}).to eq([])
      end

      it 'shows conversation when current user is hidden' do
        user.update_attributes(hidden_reason: 'hidden user')
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => Conversation.where(target_user_id: user.id).as_json(include:  :most_recent_message, current_user: user, rating_count_for_user: user, unread_count_for_user_id: user.id) })
      end

      it 'hides conversation when both users are hidden' do
        user.update_attributes(hidden_reason: 'hidden user')
        user2.update_attributes(hidden_reason: 'hidden user')
        get :by_user, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => [] })
      end
    end

  end

  describe 'GET /users/:user_id/conversations/by_friends' do
    let(:user2) { Fabricate(:user) }
    let(:user3) { Fabricate(:user) }

    describe 'current user is initiating conversation' do
      # don't name this just :post as it will collide with `post` method for Controller DSL to make a POST call
      let(:post_by_user2) { Fabricate(:post, user: user2) }
      let(:post_by_user3) { Fabricate(:post, user: user3) }

      before(:each) do
        # create friendship
        friendship = Friendship.create(user: user, friend: user2)
        friendship2 = Friendship.create(user: user2, friend: user)

        # initiate a Conversation by replying to a Post...
        message = Fabricate(:user_message, user: user, recipient_user: user2, initiating_post: post_by_user2)

        # initiate a Conversation by replying to a Post...
        message1 = Fabricate(:user_message, user: user, recipient_user: user3, initiating_post: post_by_user3)
        message1.conversation.update_attributes(is_active: true, expires_at: Time.current + 1.day)

        # set it active and expire in the future...
        message.conversation.update_attributes(is_active: true, expires_at: Time.current + 1.day)
        expect(Conversation.where(initiating_user_id: user.id).length).to eq 2
      end

      it 'shows conversation when neither user is hidden' do
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        friend_conversations = user.friends.map{|f| Conversation.for_users(user.id, f.friend.id) }
        expect(JSON.parse(response.body)).to eq({ 'results' => friend_conversations.as_json(include:  :most_recent_message, current_user: user, rating_count_for_user: user, unread_count_for_user_id: user.id) })
      end

      it 'hides conversation when target user is hidden' do
        user2.update_attributes(hidden_reason: 'hidden user')
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => [] })
      end

      it 'hides conversation when current/initiating user hides the conversation' do
        conversation = Conversation.for_users(user.id, user2.id)
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)["results"].map{|r| r["id"]}).to eq([conversation.id])
        put :hide, {withUserId: user2.id}
        expect(response.status).to eq 200
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)["results"].map{|r| r["id"]}).to eq([])
      end

      it 'shows conversation when current user is hidden' do
        user.update_attributes(hidden_reason: 'hidden user')
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        friend_conversations = user.friends.map{|f| Conversation.for_users(user.id, f.friend.id) }
        expect(JSON.parse(response.body)).to eq({ 'results' => friend_conversations.as_json(include:  :most_recent_message, current_user: user, rating_count_for_user: user, unread_count_for_user_id: user.id) })
      end

      it 'hides conversation when both users are hidden' do
        user.update_attributes(hidden_reason: 'hidden user')
        user2.update_attributes(hidden_reason: 'hidden user')
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => [] })
      end

      it 'excludes non-friend conversations' do
        user.friends.destroy_all
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)['results'].length).to eq(0)
        expect(Conversation.for_user_id(user.id).length).to eq(2)
      end
    end

    describe 'current user is target of conversation' do
      # don't name this just :post as it will collide with `post` method for Controller DSL to make a POST call
      let(:post_by_user) { Fabricate(:post, user: user) }

      before(:each) do
        # create friendship
        friendship = Friendship.create(user: user, friend: user2)
        friendship2 = Friendship.create(user: user2, friend: user)

        # initiate a Conversation by replying to a Post...
        message = Fabricate(:user_message, user: user2, recipient_user: user, initiating_post: post_by_user)
        # set it active and expire in the future...
        message.conversation.update_attributes(is_active: true, expires_at: Time.current + 1.day)
        expect(Conversation.where(target_user_id: user.id).length).to eq 1
      end

      it 'shows conversation when neither user is hidden' do
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => Conversation.where(target_user_id: user.id).as_json(include:  :most_recent_message, current_user: user, rating_count_for_user: user, unread_count_for_user_id: user.id) })
      end

      it 'hides conversation when initiating user is hidden' do
        user2.update_attributes(hidden_reason: 'hidden user')
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => [] })
      end

      it 'hides conversation when current/target user hides the conversation' do
        conversation = Conversation.for_users(user.id, user2.id)
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)["results"].map{|r| r["id"]}).to eq([conversation.id])
        put :hide, {withUserId: user2.id}
        expect(response.status).to eq 200
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)["results"].map{|r| r["id"]}).to eq([])
      end

      it 'shows conversation when current user is hidden' do
        user.update_attributes(hidden_reason: 'hidden user')
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => Conversation.where(target_user_id: user.id).as_json(include:  :most_recent_message, current_user: user, rating_count_for_user: user, unread_count_for_user_id: user.id) })
      end

      it 'hides conversation when both users are hidden' do
        user.update_attributes(hidden_reason: 'hidden user')
        user2.update_attributes(hidden_reason: 'hidden user')
        get :by_friend, { user_id: user.id }
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'results' => [] })
      end
    end
  end

end
