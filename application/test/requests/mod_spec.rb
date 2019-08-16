require 'spec_helper'
require 'sidekiq/testing'

describe "Mod" do
  include ActiveJob::TestHelper
  let(:user) { Fabricate(:user, admin: true) }
  let(:user_w_photo) { Fabricate(:user_with_photo) }
  let(:user_w_needs_moderation_photo) { Fabricate(:user_with_needs_moderation_photo) }
  let(:access_token) { JsonWebToken.encode(user_id: user.id).access_token }
  let(:access_token_w_photo) { JsonWebToken.encode(user_id: user_w_photo.id).access_token }
  let(:access_token_needs_moderation) { JsonWebToken.encode(user_id: user_w_needs_moderation_photo.id).access_token }
  let(:facebook_auth) { Fabricate(:external_auth_with_facebook, user: user) }
  let(:facebook_auth_w_photo) { Fabricate(:external_auth_with_facebook, user: user_w_photo) }
  let(:facebook_auth_needs_moderation) { Fabricate(:external_auth_with_facebook, user: user_w_needs_moderation_photo) }
  let(:token) { Fabricate(:token, user: user, hashed_access_token: Digest::SHA2.hexdigest(access_token), provider: 'facebook') }
  let(:token_w_photo) { Fabricate(:token, user: user_w_photo, hashed_access_token: Digest::SHA2.hexdigest(access_token_w_photo), provider: 'facebook') }
  let(:token_needs_moderation) { Fabricate(:token, user: user_w_needs_moderation_photo, hashed_access_token: Digest::SHA2.hexdigest(access_token_needs_moderation), provider: 'facebook') }
  let(:headers) {
    {
      'Authorization' => "Bearer #{access_token}",
      'Provider' => 'facebook',
      'HTTP_ACCEPT' => 'application/json',
      'ACCEPT' => 'application/json'
    }
  }
  let(:headers_w_photo) {
    {
      'Authorization' => "Bearer #{access_token_w_photo}",
      'Provider' => 'facebook',
      'HTTP_ACCEPT' => 'application/json',
      'ACCEPT' => 'application/json'
    }
  }
  let(:headers_needs_moderation) {
    {
      'Authorization' => "Bearer #{access_token_needs_moderation}",
      'Provider' => 'facebook',
      'HTTP_ACCEPT' => 'application/json',
      'ACCEPT' => 'application/json'
    }
  }

  before(:each) do
    Timecop.scale(3600) # turn seconds into hours to help testing
    user
    user_w_photo
    user_w_needs_moderation_photo
    # override custom instance attribute that a reloaded User object will never have and is screwing up our testing
    user.is_new = false
    user_w_photo.is_new = false
    user_w_needs_moderation_photo.is_new = false
    token
    token_w_photo
    token_needs_moderation

    allow_any_instance_of(Aws::SNS::Client).to receive(:publish).and_return(true)
  end

  describe "moderate user photos that need moderation" do
    it 'marks user_photos as moderated' do

      user_photo = user_w_needs_moderation_photo.all_user_photos.first
      expect(user_photo.needs_moderation).to eq true
      expect(user_photo.moderated).to eq false

      # moderate user photos
      post "/mod/user_photos", {moderated: [user_w_needs_moderation_photo.all_user_photos.first.id]}, headers

      user_photo.reload

      expect(response.status).to eq 200
      expect(user_photo.moderated).to eq true
    end

    it 'delete user_photos that are marked for deletion' do

      user_photo = user_w_needs_moderation_photo.all_user_photos.first
      user_photo_id = user_photo.id
      expect(user_photo.needs_moderation).to eq true
      expect(user_photo.moderated).to eq false

      # moderate user photos
      post "/mod/user_photos", {deleted: [user_photo_id]}, headers

      expect(response.status).to eq 200
      expect(UserPhoto.find_by(id: user_photo_id)).to eq nil
    end
  end

end
