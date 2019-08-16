# frozen_string_literal: true

describe UsersController, type: :controller do

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
  let(:reset_password_token) { 'TOKEN_STRING' }

  before(:each) do
    user
    # override custom instance attribute that a reloaded User object will never have and is screwing up our testing
    user.is_new = false
    token
    facebook_auth
    allow(ExternalAuthProvider).to receive(:external_id_for_token).with(access_token, 'facebook').and_return(facebook_auth.provider_id)
    request.headers.merge!(headers)
    allow(Branch).to receive(:set_password).and_return(reset_password_token)
    request.accept = 'application/json'
  end

  describe 'External IP' do
    let(:user) { Fabricate(:user) }
    it 'sets ban reason to "outside us"' do
      controller.request.remote_addr = '187.210.6.44'
      get :show, { id: user.id }
      user.reload
      expect(response.status).to eq 401
      expect(user.ban_reason).to eq "outside us"
    end

    it 'set the ip back to us' do
      user.ban_with_reason "outside us"
      controller.request.remote_addr = '47.17.179.46'
      get :show, { id: user.id }
      user.reload
      expect(response.status).to_not eq 401
    end
  end


  describe 'GET /users/:id/activity_count' do
    it 'return unread user messages from a user in an active conversation' do
      sender = Fabricate(:user)
      user_message = Fabricate(:user_message, user: sender, recipient_user: user)
      user_message.conversation.is_active = true
      user_message.conversation.save

      get :activity_count, {id: user.id}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({"activity" => 1, "unread_view_count" => 0, "unread_conversation_count" => 1, "unread_friend_message_count" => 0})
    end

    it 'does not count unread user messages from a user in an inactive or expired conversation' do
      sender = Fabricate(:user)
      user_message = Fabricate(:user_message, user: sender, recipient_user: user)
      user_message.conversation.is_active = false
      user_message.conversation.expires_at = Time.now - 1.hour
      user_message.conversation.save

      get :activity_count, {id: user.id}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({"activity" => 0, "unread_view_count" => 0, "unread_conversation_count" => 0, "unread_friend_message_count" => 0})
    end

    it 'does not count unread user messages from a hidden user in an active conversation' do
      sender = Fabricate(:user)
      user_message = Fabricate(:user_message, user: sender, recipient_user: user)
      user_message.conversation.is_active = true
      sender.hidden_reason = "i am hidden"
      sender.save
      user_message.conversation.save

      get :activity_count, {id: user.id}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({"activity" => 0, "unread_view_count" => 0, "unread_conversation_count" => 0, "unread_friend_message_count" => 0})
    end

    it 'returns count unread friend messages from a friend in an active conversation' do
      sender = Fabricate(:user)
      # establish friendship
      friendship1 = Friendship.create(user: user, friend: sender)
      friendship2 = Friendship.create(user: sender, friend: user)

      user_message = Fabricate(:user_message, user: sender, recipient_user: user)
      user_message.conversation.is_active = true
      user_message.conversation.save

      get :activity_count, {id: user.id}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)).to eq({"activity" => 1, "unread_view_count" => 0, "unread_conversation_count" => 1, "unread_friend_message_count" => 1})
    end
  end

  describe 'GET /users/:id' do
    describe 'plain user' do
      let(:user) { Fabricate(:user) }

      it 'returns user object in results array' do
        get :show, { id: user.id }
        user.reload
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'result' => user.as_json(include: [:user_photos, :location, :user_settings], methods: [:virtual_currency_balance, :reply_count, :post_rating_count, :stars_received_count, :post_rating_received_count], current_user_id: user.id), 'conversation_id' => nil, 'unread_message_count' => nil, 'active_conversation_id' => nil })
      end
    end

    describe 'user with location' do
      let(:user) { Fabricate(:user_with_location) }

      it 'returns user object in results array including location object' do
        get :show, { id: user.id }
        user.reload
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'result' => user.as_json(include: [:user_photos, :location, :user_settings], methods: [:virtual_currency_balance, :reply_count, :post_rating_count, :stars_received_count, :post_rating_received_count], current_user_id: user.id), 'conversation_id' => nil, 'unread_message_count' => nil, 'active_conversation_id' => nil })
      end
    end

    describe 'virtual currency balance' do
      let(:user) { Fabricate(:user) }

      it 'returns the virtual currency balance' do
        user.virtual_currency_account.update_attribute :balance, 10
        get :show, { id: user.id }
        user.reload
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'result' => user.as_json(include: [:user_photos, :location, :user_settings], methods: [:virtual_currency_balance, :reply_count, :post_rating_count, :stars_received_count, :post_rating_received_count], current_user_id: user.id), 'conversation_id' => nil, 'unread_message_count' => nil, 'active_conversation_id' => nil })
        parsed_user = JSON.parse(response.body)
        expect(parsed_user['result']['virtual_currency_balance']).to eq(10)
      end
    end

    describe 'Use old token to see data' do
      let(:user) { Fabricate(:user) }
      let(:headers) {
        {
          'Authorization' => "Bearer #{JsonWebToken.encode(user_id: user.id).access_token}",
          'Provider' => 'facebook'
        }
      }
      let(:successful_auth) {
        OpenStruct.new(
          first_name: user.first_name,
          last_name: user.last_name,
          email: user.email,
          gender: user.gender,
          birthday: user.dob.strftime('%m/%d/%Y')
        )
      }

      before(:each) do
        allow_any_instance_of(Koala::Facebook::API).to receive(:get_object).and_return(successful_auth)
        request.headers.merge!(headers)
      end

      it 'returns the virtual currency balance' do
        user.virtual_currency_account.update_attribute :balance, 10
        get :show, { id: user.id }
        user.reload
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'result' => user.as_json(include: [:user_photos, :location, :user_settings], methods: [:virtual_currency_balance, :reply_count, :post_rating_count, :stars_received_count, :post_rating_received_count], current_user_id: user.id), 'conversation_id' => nil, 'unread_message_count' => nil, 'active_conversation_id' => nil })
        parsed_user = JSON.parse(response.body)
        expect(parsed_user['result']['virtual_currency_balance']).to eq(10)
      end
    end

    describe 'Use old token to see data' do
      let(:user) { Fabricate(:user) }
      let(:headers) {
        {
          'Authorization' => "Bearer #{JsonWebToken.encode(user_id: user.id).access_token}",
          'Provider' => 'facebook'
        }
      }
      let(:successful_auth) {
        OpenStruct.new(
          first_name: user.first_name,
          last_name: user.last_name,
          email: user.email,
          gender: user.gender,
          birthday: user.dob.strftime('%m/%d/%Y')
        )
      }

      before(:each) do
        allow_any_instance_of(Koala::Facebook::API).to receive(:get_object).and_return(successful_auth)
        request.headers.merge!(headers)
      end

      it 'returns the virtual currency balance' do
        user.virtual_currency_account.update_attribute :balance, 10
        get :show, { id: user.id }
        user.reload
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'result' => user.as_json(include: [:user_photos, :location, :user_settings], methods: [:virtual_currency_balance, :reply_count, :post_rating_count, :stars_received_count, :post_rating_received_count], current_user_id: user.id), 'conversation_id' => nil, 'unread_message_count' => nil, 'active_conversation_id' => nil })
        parsed_user = JSON.parse(response.body)
        expect(parsed_user['result']['virtual_currency_balance']).to eq(10)
      end
    end

    describe 'Use old token to see data' do
      let(:user) { Fabricate(:user) }
      let(:headers) {
        {
          'Authorization' => "Bearer #{access_token}",
          'Provider' => 'facebook'
        }
      }
      let(:successful_auth) {
        OpenStruct.new(
          first_name: user.first_name,
          last_name: user.last_name,
          email: user.email,
          gender: user.gender,
          birthday: user.dob.strftime('%m/%d/%Y')
        )
      }

      before(:each) do
        allow_any_instance_of(Koala::Facebook::API).to receive(:get_object).and_return(successful_auth)
        request.headers.merge!(headers)
      end

      it 'returns the virtual currency balance' do
        user.virtual_currency_account.update_attribute :balance, 10
        get :show, { id: user.id }
        user.reload
        expect(response.status).to eq 200
        expect(JSON.parse(response.body)).to eq({ 'result' => user.as_json(include: [:user_photos, :location, :user_settings], methods: [:virtual_currency_balance, :reply_count, :post_rating_count, :stars_received_count, :post_rating_received_count], current_user_id: user.id), 'conversation_id' => nil, 'unread_message_count' => nil, 'active_conversation_id' => nil })
        parsed_user = JSON.parse(response.body)
        expect(parsed_user['result']['virtual_currency_balance']).to eq(10)
      end
    end

  end

  describe 'PUT /users/:id' do
    let(:user) { Fabricate(:user) }

    describe 'with dob' do
      let(:dob) { Date.parse('2000-01-01').in_time_zone }

      before(:each) do
        user.create_settings
      end

      it 'allows update if user has not exceeded MAX_NUM_DOB_UPDATES' do
        expect(user.user_settings.num_dob_updates).to be nil
        put :update, { id: user.id, user: { dob: dob } }
        user.reload
        expect(response.status).to eq 200
        expect(user.dob).to eq dob
        expect(user.user_settings.num_dob_updates).to eq 1
      end

      it 'returns 400 BAD REQUEST if user update would exceed MAX_NUM_DOB_UPDATES' do
        user.user_settings.update_attributes!(num_dob_updates: CONFIG[:max_num_dob_updates])
        put :update, { id: user.id, user: { dob: dob } }
        user.reload
        expect(response.status).to eq 400
        expect(response.body).to eq({ error: 'Exceeded # of updates.' }.to_json)
        expect(user.user_settings.num_dob_updates).to eq CONFIG[:max_num_dob_updates]
      end

      it 'allows update if user dob update count equals >= MAX but dob itself is not modified' do
        user.user_settings.update_attributes!(num_dob_updates: CONFIG[:max_num_dob_updates])
        put :update, { id: user.id, user: { dob: user.dob } }
        user.reload
        expect(response.status).to eq 200
        expect(user.user_settings.num_dob_updates).to eq (CONFIG[:max_num_dob_updates] + 1)
      end
    end

    describe 'with location' do
      let(:location_attributes) { Fabricate.attributes_for(:location) }

      it 'saves location attributes on associated Location record' do
        now = Time.current
        Timecop.travel(now) do
          put :update, { id: user.id, user: { location_attributes: location_attributes } }
          user.reload
          expect(response.status).to eq 200
          expect(JSON.parse(response.body)).to eq user.as_json(include: :location)
          expect(user.location.city).to eq location_attributes['city']
          expect(user.location.state_province).to eq location_attributes['state_province']
          expect(user.location.longitude.round(1)).to eq location_attributes['longitude'].round(1)
          expect(user.location.latitude.round(1)).to eq location_attributes['latitude'].round(1)
        end
      end

      describe 'reverse-geocoding' do
        let(:geo_response) do
          File.read(Rails.root.join('spec/fixtures/google/geocode_response_san_francisco.json'))
        end

        before(:each) do
          stub_request(:get, "https://maps.googleapis.com/maps/api/geocode/json?key=#{configatron.google.server_key}&language=en&latlng=#{[sf.latitude, sf.longitude].join(',')}&sensor=false")
            .with(
              headers: {
                'Accept' => '*/*',
                'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
                'User-Agent' => 'Ruby'
              }
            )
            .to_return(status: 200, body: geo_response, headers: {})
        end

        describe 'no state_province provided but with lat/long' do
          let(:sf) { Fabricate(:san_francisco) }

          it 'reverse geocodes based on lat/long and populates Location record' do
            now = Time.current
            Timecop.travel(now) do
              put :update, { id: user.id, user: { location_attributes: Fabricate.attributes_for(:san_francisco).except(:city, :state_province) } }
              user.reload
              expect(response.status).to eq 200
              expect(user.location.city).to eq sf.city
              expect(user.location.state_province).to eq sf.state_province
            end
          end
        end

        describe 'state abbreviation provided but with lat/long' do
          let(:sf) { Fabricate(:san_francisco_short_CA) }

          it 'geocodes based on lat/long and populates Location record' do
            now = Time.current
            Timecop.travel(now) do
              put :update, { id: user.id, user: { location_attributes: Fabricate.attributes_for(:san_francisco_short_CA).except(:city) } }
              user.reload
              expect(response.status).to eq 200
              expect(user.location.city).to eq sf.city
              expect(user.location.state_province).to eq 'California'
            end
          end
        end
      end
    end
  end

  describe 'POST /users/' do
    let(:new_user) {
      {
        email: Faker::Internet.email , first_name: "First100", gender: [GENDER_MALE, GENDER_FEMALE, UNKNOWN].sample, phone: "1234567890", dob: Faker::Date.birthday(18, 65), user_photo: {
          source: 'camera', base64_image: "data:image/jpeg;base64,/9j/4AAQSkZJRgABAAEAYABgAAD//gAfTEVBRCBUZWNobm9sb2dpZXMgSW5jLiBWMS4wMQD/2wCEAAUFBQgFCAwHBwwMCQkJDA0MDAwMDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0BBQgICgcKDAcHDA0MCgwNDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDf/EAaIAAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKCwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoLEAACAQMDAgQDBQUEBAAAAX0BAgMABBEFEiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+foRAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/AABEIAAoACgMBEQACEQEDEQH/2gAMAwEAAhEDEQA/APP6+VP6LHV0pKy0ENrmGOrqWy9BH//Z"
        }
      }
    }

    before(:each) do
      ImageUploader.any_instance.stub(:store!)
    end

    it 'return a new user' do
      post :create, {user: new_user}
      expect(response.status).to eq 201
      expect(JSON.parse(response.body)["user"]["first_name"]).to eq("First100")
    end

    it 'return 422 if user registers with an existing email' do
      post :create, {user: new_user}
      post :create, {user: new_user}
      expect(response.status).to eq 422
      expect(JSON.parse(response.body)["message"]).to eq "Email has already been taken. "
    end

    describe 'underage user' do
      let(:underage_user) {
        {
          email: Faker::Internet.email , first_name: "First100", gender: [GENDER_MALE, GENDER_FEMALE, UNKNOWN].sample, phone: "1234567890", dob: Faker::Date.birthday(13, 17), user_photo: {
            source: 'camera', base64_image: "data:image/jpeg;base64,/9j/4AAQSkZJRgABAAEAYABgAAD//gAfTEVBRCBUZWNobm9sb2dpZXMgSW5jLiBWMS4wMQD/2wCEAAUFBQgFCAwHBwwMCQkJDA0MDAwMDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0BBQgICgcKDAcHDA0MCgwNDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDf/EAaIAAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKCwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoLEAACAQMDAgQDBQUEBAAAAX0BAgMABBEFEiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+foRAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/AABEIAAoACgMBEQACEQEDEQH/2gAMAwEAAhEDEQA/APP6+VP6LHV0pKy0ENrmGOrqWy9BH//Z"
          }
        }
      }

      it 'returns 403 but creates a user account that is banned and hidden' do
        post :create, {user: underage_user}
        expect(response.status).to eq 403
        expect(User.last.ban_reason).to eq "You must be at least 18 years old to use Friended."
        expect(User.last.hidden_reason).to eq "You must be at least 18 years old to use Friended."
      end
    end
  end

  describe 'GET /users/email_exists/' do
    # let(:user) { Fabricate(:user) }
    it 'Verify if the email exists' do
      get :email_exists, {email: Faker::Internet.email}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["message"]).to eq("Valid email")
    end
  end

  describe 'GET /users/forgot_password/' do
    let(:user) { Fabricate(:user) }

    it 'forgot_password' do
      get :forgot_password, {email: user.email}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["message"]).to eq("New password request sent")
    end
  end

  describe 'PUT /users/set_password/' do
    let(:user) { Fabricate(:user) }
    let(:password_reset_access_token) { JsonWebToken.encode({user_id: user.id, expires_on: Time.now + 1.day}).access_token }
    let(:headers) {
      {
        'Authorization' => "Bearer #{password_reset_access_token}"
      }
    }

    before(:each) do
      request.headers.merge!(headers)
      user.reset_password_token = password_reset_access_token
      user.save!
    end
    it 'set_password' do
      put :set_password, {password: "fakepass"}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["user"]["first_name"]).to eq(user.first_name)
    end
  end

  describe 'PUT /users/set_password/' do
    let(:user) { Fabricate(:user) }
    let(:password_reset_access_token) { JsonWebToken.encode({user_id: user.id, expires_on: Time.now - 1.day}).access_token }
    let(:headers) {
      {
        'Authorization' => "Bearer #{password_reset_access_token}"
      }
    }

    before(:each) do
      request.headers.merge!(headers)
      user.reset_password_token = password_reset_access_token
      user.save!
    end
    it 'set_password fail if the token is more than 1 day old' do
      put :set_password, {password: "fakepass"}
      expect(response.status).to eq 401
      expect(JSON.parse(response.body)["error"]).to eq("expired_token")
    end
  end

end