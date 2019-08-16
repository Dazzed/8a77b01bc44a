# frozen_string_literal: true

describe PageViewsController, type: :controller do
  let(:user) { Fabricate(:user) }
  let(:other_user) { Fabricate(:user) }
  let(:blocking_user) { Fabricate(:user) }
  let(:blocked_user) { Fabricate(:user) }
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
    other_user
    blocking_user
    blocked_user
    # override custom instance attribute that a reloaded User object will never have and is screwing up our testing
    user.is_new = false
    other_user.is_new = false
    blocking_user.is_new = false
    blocked_user.is_new = false
    token
    facebook_auth
    allow(ExternalAuthProvider).to receive(:external_id_for_token).with(access_token, 'facebook').and_return(facebook_auth.provider_id)
    request.headers.merge!(headers)
    request.accept = 'application/json'
  end

  describe 'POST /users/:user_id/page_views' do
    it 'creates a page view' do
      post :create, { user_id: other_user.id }
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({ 'page_view' => PageView.where(user: user, page_id: other_user, page_type: "user").first.as_json })
    end
  end

  describe 'GET /users/:user_id/page_views' do
    it 'gets a summary of recent page views' do
      users = []
      6.times { users.push(Fabricate(:user)) }
      users.each { |u| PageView.add_for_user user, u }
      get :index, { user_id: user.id, summary: "1" }
      expect(response.status).to eq 200
      results = JSON.parse(response.body)["results"]
      expect(results.count).to eq 3
    end

    it 'returns 403 for a full list if not a premium user' do
      users = []
      10.times { users.push(Fabricate(:user)) }
      users.each { |u| PageView.add_for_user user, u }
      get :index, { user_id: user.id }
      expect(response.status).to eq 403
    end

    describe 'user is a premium subscriber' do
      it 'gets a full list page views' do
        user.user_settings.update_attribute :pro_subscription_expiration, Time.now + 1.day
        users = []
        17.times { users.push(Fabricate(:user)) }
        users.each { |u| PageView.add_for_user user, u }
        get :index, { user_id: user.id }
        expect(response.status).to eq 200
        results = JSON.parse(response.body)["results"]
        expect(results.count).to eq 17
      end

      it 'respects offset and limit' do
        user.user_settings.update_attribute :pro_subscription_expiration, Time.now + 1.day
        users = []
        17.times { users.push(Fabricate(:user)) }
        users.each { |u| PageView.add_for_user user, u }
        old_viewed_date = user.user_settings.last_viewed_profile_views
        page_views = PageView.where(page_id: user.id).where(page_type: "user").order("created_at desc").offset(5).limit(5).as_json( :include => :user, :new_since => old_viewed_date)
        get :index, { user_id: user.id, offset: 5, max: 5 }
        expect(response.status).to eq 200
        results = JSON.parse(response.body)["results"]
        expect(results.count).to eq 5
        expect(results.map{|r| r["id"]}).to eq(page_views.map{|v| v["id"]})
      end

      it 'excludes users that blocked me and users I block' do
        user.user_settings.update_attribute :pro_subscription_expiration, Time.now + 1.day
        users = []
        8.times { users.push(Fabricate(:user)) }
        users.each { |u| PageView.add_for_user user, u }
        blocking_users = []
        4.times do |i|
          UserBlock.create(user: users[i], blocked_user_id: user.id)
          blocking_users.push(users[i])
        end
        users = users - blocking_users
        blocked_users = []
        2.times do |i|
          UserBlock.create(user: user, blocked_user_id: users[i].id)
          blocked_users.push(users[i])
        end
        old_viewed_date = user.user_settings.last_viewed_profile_views
        page_views = PageView.where(page_id: user.id).where(page_type: "user").order("created_at desc").offset(5).limit(5).as_json( :include => :user, :new_since => old_viewed_date)
        get :index, { user_id: user.id }
        expect(response.status).to eq 200
        results = JSON.parse(response.body)["results"]
        expect(results.count).to eq 2
        # expect(results.map{|r| r["id"]}).to eq(page_views.map{|v| v["id"]})
      end
    end
  end

end
