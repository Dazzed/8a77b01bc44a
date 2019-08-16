# frozen_string_literal: true

describe VirtualProductTransactionsController, type: :controller do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user) }
  let(:access_token) { JsonWebToken.encode(user_id: user.id).access_token }
  let(:user2) { Fabricate(:user) }
  let(:facebook_auth) { Fabricate(:external_auth_with_facebook, user: user) }
  let(:token) { Fabricate(:token, user: user, hashed_access_token: Digest::SHA2.hexdigest(access_token), provider: 'facebook') }
  let(:headers) {
    {
      'Authorization' => "Bearer #{access_token}",
      'Provider' => 'facebook'
    }
  }

  before(:each) do
    user
    user2
    token
    facebook_auth
    allow(ExternalAuthProvider).to receive(:external_id_for_token).with(access_token, 'facebook').and_return(facebook_auth.provider_id)
    request.headers.merge!(headers)
  end

  describe 'GET index' do
    it 'redirects with error message if no :user_id provided' do
      get :index
      expect(response.status).to eq 302
      expect(response.body).to eq "<html><body>You are being <a href=\"http://test.host/\">redirected</a>.</body></html>"
    end

    it 'redirects with error message if :user_id not found' do
      get :index, user_id: 999_999
      expect(response.status).to eq 302
      expect(response.body).to eq "<html><body>You are being <a href=\"http://test.host/\">redirected</a>.</body></html>"
    end

    it 'renders empty array when no VirtualProductTransactions' do
      get :index, user_id: user.id
      expect(JSON.parse(response.body)).to eq({ 'results' => [] })
    end

    it 'renders only VirtualProductTransactions for :user_id by default' do
      user2 = Fabricate(:user)
      target_user = Fabricate(:user)
      transaction1 = Fabricate(:virtual_product_transaction, user: user, recipient_user: target_user, virtual_product_type_id: 1)
      # another transaction for a different user
      Fabricate(:virtual_product_transaction, user: user2, recipient_user: target_user, virtual_product_type_id: 1)
      get :index, user_id: user.id
      expect(JSON.parse(response.body)).to eq({ 'results' => [transaction1.as_json(include: [:virtual_product_type])] })
    end

    pending 'renders VirtualProductTransactions for :user_id as recipient_user when :received parameter present'

    pending 'renders VirtualProductTransactions for :user_id as gift recipient when :gifts parameter present'
  end

  describe 'POST create' do
    describe 'validation' do
      it 'returns 400 Bad Request if no product type supplied' do
        post :create, user_id: user.id
        expect(response.status).to eq 400
        expect(response.body).to eq({ error: 'No valid type was supplied.', virtual_balance: user.virtual_currency_account.balance }.to_json)
      end

      it 'returns 400 Bad Request if invalid product type supplied' do
        post :create, user_id: user.id, type: 'blahblah'
        expect(response.status).to eq 400
        expect(response.body).to eq({ error: 'No valid type was supplied.', virtual_balance: user.virtual_currency_account.balance }.to_json)
      end

      it 'returns 403 Forbidden if recipient has blocked user' do
        skip
      end

      it 'returns 403 Forbidden if user has blocked recipient' do
        skip
      end

      it 'returns 400 if user doesn\'t have enough balance for product type' do
        post :create, user_id: user.id, type: 'pro_subscription'
        expect(response.status).to eq 403
        expect(response.body).to eq({ error: 'You need more diamonds to complete this action.', virtual_balance: user.virtual_currency_account.balance }.to_json)
      end

      it 'returns 400 if quantity provided exceeds product type max_quantity' do
        user.virtual_currency_account.credit_balance!(100)
        target_user = Fabricate(:user)
        post :create, user_id: target_user.id, type: 'gift.champagne', virtual_product_transaction: { quantity: 2 }
        expect(response.status).to eq 403
        expect(response.body).to eq({ error: 'This product quantity exceeds its max quantity.', virtual_balance: user.virtual_currency_account.balance }.to_json)
      end
    end

    describe 'purchasing gifts' do
      before(:each) do
        # construct gift product
        # credit user enough balance to purchase
      end

      it 'debits user virtual currency balance appropriately' do
        skip
      end

      it 'does nothing if no image_url on gift product type' do
        skip
      end

      it 'creates Conversation between user and recipient if none previously existed' do
        skip
      end

      it 'creates UserMessage between user and recipient, referring to original Post' do
        product_type = VirtualProductType.where(giftable: true).first
        assert_enqueued_with(
          job: SendAPNJob
        ) do
          assert_enqueued_with(
            job: FirebaseSendMessageJob
          ) do
            post :create, type: product_type.code, user_id: user2.id
            expect(response.status).to eq 200
            parsed_response = JSON.parse(response.body)
            virtual_product_transaction_id = parsed_response["result"]["id"]
            expect(virtual_product_transaction_id).to eq(UserMessage.last.virtual_product_transaction_id)
          end
        end
      end
    end

    describe 'post now' do
      it 'debits user amount of Post Now product' do
        product_type = VirtualProductType.find_by(code: 'post_now')
        post :create, type: 'post_now'
        expect(response.status).to eq 200
        user.virtual_currency_account.reload
        # every new User has a starting balance
        expect(user.virtual_currency_account.balance).to eq VirtualCurrencyAccount::STARTING_BALANCE - product_type.cost
      end

      it 'resets user\'s new post timer' do
        expect_any_instance_of(User).to receive(:reset_post_allowed_interval!)
        post :create, type: 'post_now'
        expect(response.status).to eq 200
      end
    end

    describe 'boost post' do
      it 'returns 400 Bad Request if no post_id supplied' do
        post :create, type: 'boost_post'
        expect(response.status).to eq 400
        expect(response.body).to eq({ error: 'No post_id to boost supplied.', virtual_balance: user.virtual_currency_account.balance }.to_json)
      end

      it 'returns 404 Not Found  if post_id supplied belongs to another user' do
        user2 = Fabricate(:user)
        new_post = Fabricate(:post, user: user2)
        post :create, type: 'boost_post', post_id: new_post.id
        expect(response.status).to eq 404
        expect(response.body).to eq({ error: 'No such post for current user.', virtual_balance: user.virtual_currency_account.balance }.to_json)
      end

      it 'debits user amount of Boost Post product' do
        product_type = VirtualProductType.find_by(code: 'boost_post')
        new_post = Fabricate(:post, user: user)
        post :create, type: 'boost_post', post_id: new_post.id
        expect(response.status).to eq 200
        user.virtual_currency_account.reload
        # every new User has a starting balance
        expect(user.virtual_currency_account.balance).to eq VirtualCurrencyAccount::STARTING_BALANCE - product_type.cost
      end

      it 'raises user\'s post to top of feed' do
        now = Time.current.to_date.to_datetime # MySQL & Rails < 5.x have a problem with timestamp precision so cap to start of day
        Timecop.freeze(now) do
          new_post = Fabricate(:post, user: user)
          expect(new_post.created_at).to eq now
          expect(new_post.updated_at).to eq now
          post :create, type: 'boost_post', post_id: new_post.id
          expect(response.status).to eq 200
          new_post.reload
          expect(new_post.created_at).to eq now + Post::BOOST_POST_INTERVAL
          expect(new_post.updated_at).to eq now + Post::BOOST_POST_INTERVAL
        end
      end
    end
  end
end
