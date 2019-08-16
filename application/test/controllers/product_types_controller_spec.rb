# frozen_string_literal: true

describe ProductTypesController, type: :controller do
  render_views

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

  describe 'GET /product_types' do
    it 'returns all Product Types' do
      payupfront = Fabricate(:product_type, payupfront: true)
      paywall = Fabricate(:product_type, paywall: true)
      tier1 = Fabricate(:product_type, tiers: true, order: 11)
      tier2 = Fabricate(:product_type, tiers: true, order: 22)
      get :index
      expect(response.status).to eq 200
      locals = {
        payupfront: payupfront,
        paywall: paywall,
        tiers: [tier1, tier2]
      }
      json = JSON.parse(response.body)
      expect(json.keys).to eq %w(payupfront paywall tiers referral)
      expect(json['payupfront']['name']).to eq payupfront.name
      expect(json['paywall']['name']).to eq paywall.name
      expect(json['tiers'].first['name']).to eq tier1.name
      expect(json['tiers'].last['name']).to eq tier2.name
    end
  end
end
