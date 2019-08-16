# frozen_string_literal: true

describe UserBlocksController, type: :controller do
  let(:user) { Fabricate(:user) }
  let(:pro_user) { Fabricate(:pro_user) }
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

  describe 'POST /users/:id/user_blocks' do
    let(:user2) { Fabricate(:user) }

    describe 'params validation' do
      it 'responds with 400 for user_id same as current user' do
        post :create, { user_id: user.id }
        expect(response.status).to eq 400
        expect(response.body).to eq({ error: 'You cannot block yourself.' }.to_json)
      end
    end

    it 'allows blocking user with no block flag' do
      post :create, { user_id: user2.id }
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq UserBlock.first.as_json
    end

    it 'blocks user with block flag' do
      post :create, { user_id: user2.id, user_block: { block_flag: Enums::UserBlockFlags.ids.sample } }
      expect(response.status).to eq 200
      block = UserBlock.first
      expect(JSON.parse(response.body)).to eq block.as_json
    end

    it 'blocks user with block flag and reason text' do
      post :create, { user_id: user2.id, user_block: { block_flag: Enums::UserBlockFlags.ids.sample, reason_text: 'I only talk to girls named Bernard' } }
      expect(response.status).to eq 200
      block = UserBlock.first
      expect(JSON.parse(response.body)).to eq block.as_json
      expect(block.reason_text).to eq 'I only talk to girls named Bernard'
    end
  end
end
