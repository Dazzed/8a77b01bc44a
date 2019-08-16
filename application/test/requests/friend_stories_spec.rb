require 'spec_helper'
require 'sidekiq/testing'

describe "Friend Stories" do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user) }
  let(:friend) { Fabricate(:user) }
  let(:access_token) { JsonWebToken.encode(user_id: user.id).access_token }
  let(:access_token_friend) { JsonWebToken.encode(user_id: friend.id).access_token }
  let(:facebook_auth) { Fabricate(:external_auth_with_facebook, user: user) }
  let(:facebook_auth_friend) { Fabricate(:external_auth_with_facebook, user: friend) }
  let(:token) { Fabricate(:token, user: user, hashed_access_token: Digest::SHA2.hexdigest(access_token), provider: 'facebook') }
  let(:friend_token) { Fabricate(:token, user: friend, hashed_access_token: Digest::SHA2.hexdigest(access_token_friend), provider: 'facebook') }
  let(:headers) {
    {
      'Authorization' => "Bearer #{access_token}",
      'Provider' => 'facebook',
      'HTTP_ACCEPT' => 'application/json',
      'ACCEPT' => 'application/json'
    }
  }
  let(:headers_friend) {
    {
      'Authorization' => "Bearer #{access_token_friend}",
      'Provider' => 'facebook',
      'HTTP_ACCEPT' => 'application/json',
      'ACCEPT' => 'application/json'
    }
  }

  before(:each) do
    Timecop.scale(3600) # turn seconds into hours to help testing
    user
    friend
    # override custom instance attribute that a reloaded User object will never have and is screwing up our testing
    user.is_new = false
    friend.is_new = false
    token
    friend_token

    MediaUploader.any_instance.stub(:store!)
  end

  describe "creating friend stories" do
    it 'allows user to post a friend story with an image upload' do
      post "/users/#{user.id}/friend_stories", { file: Rack::Test::UploadedFile.new("#{Rails.root}/spec/support/attachments/test_image.jpg", 'image/jpeg') }, headers
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_story"]["media_type"]).to eq("image")
    end

    it 'allows user to post a friend story with an video upload' do
      post "/users/#{user.id}/friend_stories", { file: Rack::Test::UploadedFile.new("#{Rails.root}/spec/support/attachments/test_video.mp4", 'video/mp4') }, headers
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_story"]["media_type"]).to eq("video")
    end
  end

end
