require 'rails_helper'

describe FriendsController, type: :controller do
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

  describe 'POST /users/:user_id/friends' do
    let(:friend) { Fabricate(:user) }

    it 'fails silently if hidden user tries to send a request' do
      user.hidden_reason = "user is hidden"
      user.save
      post :create, {user_id: friend.id}
      friendship = Friendship.where(user: user, friend: friend).first
      expect(response.status).to eq 200
      expect(friendship).to eq nil
    end

    it 'allows initial request with friendship status = pending' do
      post :create, {user_id: friend.id}
      friendship = Friendship.where(user: user, friend: friend).first
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friendship"]["id"]).to eq(friendship.id)
      expect(JSON.parse(response.body)["friendship"]["user_id"]).to eq(friendship.user_id)
      expect(JSON.parse(response.body)["friendship"]["friend_id"]).to eq(friendship.friend_id)
      expect(JSON.parse(response.body)["friendship"]["status"]).to eq("pending")
    end

    it 'it returns 403 if a duplicate request is made' do
      post :create, {user_id: friend.id}
      post :create, {user_id: friend.id}
      expect(response.status).to eq 403
    end

    it 'it changes status to accepted if friend has a friendship request pending' do
      friendship = Friendship.create(user: friend, friend: user)
      post :create, {user_id: friend.id}
      friendship_accepted = Friendship.where(user: user, friend: friend).first
      friendship = Friendship.where(user: friend, friend: user).first
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friendship"]["id"]).to eq(friendship_accepted.id)
      expect(JSON.parse(response.body)["friendship"]["user_id"]).to eq(friendship_accepted.user_id)
      expect(JSON.parse(response.body)["friendship"]["friend_id"]).to eq(friendship_accepted.friend_id)
      expect(JSON.parse(response.body)["friendship"]["status"]).to eq("accepted")
      expect(friendship.status).to eq("accepted")
    end

  end

  describe 'GET /users/:user_id/friends/requests' do
    let(:friend1) { Fabricate(:user) }
    let(:friend2) { Fabricate(:user) }
    let(:friend3) { Fabricate(:user) }

    it 'return a list of pending friendship requests' do
      friendship1 = Fabricate(:friendship, user: friend1, friend: user)
      friendship2 = Fabricate(:friendship, user: friend2, friend: user)
      friendship3 = Fabricate(:friendship, user: friend3, friend: user)

      get :requests, {user_id: user.id}
      expect(response.status).to eq 200
      friend_requests = JSON.parse(response.body)["friend_requests"]
      expect(friend_requests.count).to eq(3)
      expect(friend_requests[0]["id"]).to eq(friendship1.id)
      expect(friend_requests[1]["id"]).to eq(friendship2.id)
      expect(friend_requests[2]["id"]).to eq(friendship3.id)
    end
  end

  describe 'GET /users/:user_id/friends' do
    let(:friend1) { Fabricate(:user) }
    let(:friend2) { Fabricate(:user) }
    let(:friend3) { Fabricate(:user) }

    it 'return a list friends' do
      friendship1 = Fabricate(:friendship, user: friend1, friend: user)
      friendship2 = Fabricate(:friendship, user: friend2, friend: user)
      friendship3 = Fabricate(:friendship, user: friend3, friend: user)
      friendship1_r = Fabricate(:friendship, user: user, friend: friend1)
      friendship2_r = Fabricate(:friendship, user: user, friend: friend2)
      friendship3_r = Fabricate(:friendship, user: user, friend: friend3)

      get :index, {user_id: user.id}
      expect(response.status).to eq 200
      friends = JSON.parse(response.body)["friends"]
      expect(friends.count).to eq(3)
      expect(friends[0]["id"]).to eq(friend1.id)
      expect(friends[1]["id"]).to eq(friend2.id)
      expect(friends[2]["id"]).to eq(friend3.id)
    end
  end

end
