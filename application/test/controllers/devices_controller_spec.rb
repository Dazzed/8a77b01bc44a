require 'rails_helper'

RSpec.describe DevicesController, type: :controller do
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

  describe 'POST /devices' do
    let(:user2) { Fabricate(:user) }

    it 'responds with 200 when creating a new device for current_user' do
      post :create, {device_id: "test-device-id"}
      expect(response.status).to eq 200
      device = Device.first
      expected_response = {device: device, success: true}
      expect(JSON.parse(response.body)).to eq expected_response.as_json
    end

    it 'updates uuid on user to match device uuid on success' do
      user.uuid = "initial-device-id"
      user.save
      test_device_id = "test-device-id"
      post :create, {device_id: test_device_id}
      expect(response.status).to eq 200
      device = Device.first
      expected_response = {device: device, success: true}
      expect(JSON.parse(response.body)).to eq expected_response.as_json
      user.reload
      expect(user.uuid).to eq test_device_id
    end

    it 'responds with 200 when associating a device without a user for current_user' do
      existing_device_id = "existing-device-id"
      existing_device = Device.create(uuid: existing_device_id)
      post :create, {device_id: existing_device_id}
      expect(response.status).to eq 200
      device = Device.first
      expected_response = {device: device, success: true}
      expect(JSON.parse(response.body)).to eq expected_response.as_json
    end

    it 'responds with 403 when trying to create a device already associated to another user for current_user' do
      existing_device_id = "existing-device-id"
      existing_device = Device.create(uuid: existing_device_id, user: user2)
      post :create, {device_id: existing_device_id}
      expect(response.status).to eq 403
      expected_response = {device: nil, success: false}
      expect(JSON.parse(response.body)).to eq expected_response.as_json
    end
  end

end
