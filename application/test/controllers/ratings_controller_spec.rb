# frozen_string_literal: true

require 'sidekiq/testing'

describe RatingsController, type: :controller do
  include ActiveJob::TestHelper

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

  describe 'GET /posts/:post_id/ratings' do
    let(:user2) { Fabricate(:user) }
    let(:blocked_user) { Fabricate(:user) }
    let(:blocked_by_user) { Fabricate(:user) }

    before(:each) do
      user2.is_new = false
      blocked_user.is_new = false
      blocked_by_user.is_new = false
    end

    it 'gets all ratings from a post' do
      post = Fabricate(:post, user: user)

      rating = Fabricate(:rating, user: user2, target_id: post.id, target_type: RELATIONSHIP_TYPE_POST)
      rating2 = Fabricate(:rating, user: blocked_user, target_id: post.id, target_type: RELATIONSHIP_TYPE_POST)
      rating3 = Fabricate(:rating, user: blocked_by_user, target_id: post.id, target_type: RELATIONSHIP_TYPE_POST)

      get :index, {post_id: post.id }
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["results"].count).to eq(3)
    end

    it 'does not show ratings from users who have blocked me or who i have blocked' do
      post = Fabricate(:post, user: user)

      blocked = Fabricate(:user_block, user: user, blocked_user_id: blocked_user.id)
      blocked_by = Fabricate(:user_block, user: blocked_by_user, blocked_user_id: user.id)

      rating = Fabricate(:rating, user: user2, target_id: post.id, target_type: RELATIONSHIP_TYPE_POST)
      rating2 = Fabricate(:rating, user: blocked_user, target_id: post.id, target_type: RELATIONSHIP_TYPE_POST)
      rating3 = Fabricate(:rating, user: blocked_by_user, target_id: post.id, target_type: RELATIONSHIP_TYPE_POST)

      get :index, {post_id: post.id }
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({"results" => [rating.as_json(include: :user)]})
    end
  end

  describe 'POST /posts/:post_id/ratings' do
    let(:user2) { Fabricate(:user) }
    # don't name this just :post as it will collide with `post` method for Controller DSL to make a POST call
    let(:post_by_user2) { Fabricate(:post, user: user2) }

    describe 'sending APN' do
      it 'constructs SendAPNJob with correct params for a positive rating' do
        post_by_user2 = Fabricate(:post, user: user2)
        assert_enqueued_with(
          job: SendAPNJob,
          args: [
            [user2.id],
            {
              type: 'post_hearts',
              route: {
                link: 'postActivity',
                objectId: "#{post_by_user2.id}"
              },
              toaster_body: "#{user.first_name} loved your post.",
              user_first_name: "#{user.first_name}",
              user_profile_image_url: user.profile_photo,
              silent: true
            }
          ]
        ) do
          post :create, { post_id: post_by_user2.id, rating: { value: 1 } }
          expect(response.status).to eq 200
        end
      end

      it 'constructs SendAPNJob with correct params for a negative rating' do
        post_by_user2 = Fabricate(:post, user: user2)
        assert_enqueued_with(
          job: SendAPNJob,
          args: [
            [user2.id],
            {
              type: 'post_views',
              route: {
                link: 'postActivity',
                objectId: "#{post_by_user2.id}"
              },
              toaster_body: "#{user.first_name} viewed your post.",
              user_first_name: "#{user.first_name}",
              user_profile_image_url: user.profile_photo,
              silent: true
            }]
        ) do
          post :create, { post_id: post_by_user2.id, rating: { value: -1 } }
          expect(response.status).to eq 200
        end
      end
    end
  end
end
