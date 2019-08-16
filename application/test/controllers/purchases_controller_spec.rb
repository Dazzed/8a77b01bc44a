# frozen_string_literal: true

require 'sidekiq/testing'


describe PurchasesController, type: :controller do
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
  let(:receipt_data) { Base64.encode64('receipt data') }
  let(:price) { 7.99 } # note that the Fabricator price is 9.99 and a price higher than that without pending_renewal)info consent will not be accepted.

  before(:each) do
    user
    token
    facebook_auth
    allow(ExternalAuthProvider).to receive(:external_id_for_token).with(access_token, 'facebook').and_return(facebook_auth.provider_id)
    allow_any_instance_of(Customerio::Client).to receive(:track).and_return
    request.headers.merge!(headers)
    stub_request(:put, /foundermark-friended-dev.s3.amazonaws.com/)
      .to_return(status: 200, body: "stubbed response", headers:{"Etag": nil})
  end

  describe 'POST new' do
    describe 'with only subscription product receipts' do
      let(:sample_payload) do
        JSON.parse(File.read(Rails.root.join('spec/fixtures/sample_receipt.json')))
      end

      before(:each) do
        allow(PurchaseReceipt).to receive(:verify_ios_purchase).and_return(sample_payload)
      end

      describe 'no ProductType for apple_product_id in receipt' do
        it 'stores all receipts in :latest_receipt_info array - with price nil - even if no price supplied' do
          assert_enqueued_with(job: SentryJob) do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob) do
                post :new, { receipt: sample_payload[:latest_receipt] }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['310000293756518', '70000458734964']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [true, true]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [nil, nil]
              end
            end
          end
        end
      end

      describe 'with ProductType for apple_product_id in receipt' do
        before(:each) do
          Fabricate(:pro_subscription_product)
        end

        describe 'new_trial' do
          it 'stores all receipts in :latest_receipt_info array - with price from ProductType - even if no price supplied' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt] }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['310000293756518', '70000458734964']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [true, true]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [9.99, 9.99]
              end
            end
          end

          it 'stores all receipts in [:latest_receipt_info array] and [:receipt][:in_app] even when price supplied' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt], price: price }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['310000293756518', '70000458734964']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [true, true]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [price, price]
              end
            end
          end

          it 'backfills subscription data when storing a PurchaseReceipt previously seen but with missing data' do
            target_receipt_from_payload = sample_payload['latest_receipt_info'].select{|r| r['product_id'] == "com.foundermark.Friended.prosub"}.first
            Fabricate(:purchase_receipt, user_id: user.id, transaction_id: target_receipt_from_payload['transaction_id'], quantity: nil, expires_date: nil)
            receipt = PurchaseReceipt.find_by(transaction_id: target_receipt_from_payload['transaction_id'])
            expect(receipt.quantity).to be nil
            expect(receipt.expires_date).to be nil
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: target_receipt_from_payload['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt], price: price }
                receipt.reload
                expect(receipt.quantity).to eq target_receipt_from_payload[:quantity].to_i
                expect(receipt.expires_date).to eq Time.zone.parse(target_receipt_from_payload[:expires_date])
                expect(receipt.purchase_receipt_data.get_data).to eq sample_payload[:latest_receipt]
                expect(PurchaseReceipt.all.map(&:price)).to eq [price, price]
              end
            end
          end

          it 'selects furthest expires_date from available receipts' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: receipt_data }
                user.reload
                expect(user.user_settings.pro_subscription_expiration).to eq PurchaseReceipt.find_by(transaction_id: '70000458734964').expires_date
              end
            end
          end

          it 'skips product addition for most recent receipt if already processed' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                # store initially
                post :new, { receipt: receipt_data }
                PurchaseReceipt.all.each{ |pr| pr.update_attributes(internal_status: PurchaseReceipt::STATUS_PROCESSED) }
                # now we POST again and expect no further action on user
                expect(subject).to_not receive(:add_product_for_user)
                post :new, { receipt: receipt_data }
              end
            end
          end
        end

        describe 'renewal' do
          before(:each) do
            sample_payload['latest_receipt_info'].each{ |r| r['is_trial_period'] = 'false' }
          end

          it 'stores all receipts in :latest_receipt_info array - with price from ProductType - even if no price supplied' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: 9.99, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt] }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['310000293756518', '70000458734964']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [false, false]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [9.99, 9.99]
              end
            end
          end

          it 'stores all receipts in :latest_receipt_info array even when price supplied' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: price, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt], price: price }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['310000293756518', '70000458734964']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [false, false]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [price, price]
              end
            end
          end

          it 'backfills data when storing a PurchaseReceipt previously seen but with missing data' do
            target_receipt_from_payload = sample_payload['latest_receipt_info'].select{|r| r['product_id'] == "com.foundermark.Friended.prosub"}.first
            Fabricate(:purchase_receipt, user_id: user.id, transaction_id: target_receipt_from_payload['transaction_id'], quantity: nil, expires_date: nil)
            receipt = PurchaseReceipt.find_by(transaction_id: target_receipt_from_payload['transaction_id'])
            expect(receipt.quantity).to be nil
            expect(receipt.expires_date).to be nil
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: price, product_id: target_receipt_from_payload['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt], price: price }
                receipt.reload
                expect(receipt.quantity).to eq target_receipt_from_payload[:quantity].to_i
                expect(receipt.expires_date).to eq Time.zone.parse(target_receipt_from_payload[:expires_date])
                expect(receipt.purchase_receipt_data.get_data).to eq sample_payload[:latest_receipt]
                expect(PurchaseReceipt.all.map(&:price)).to eq [price, price]
              end
            end
          end

          it 'selects furthest expires_date from available receipts' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: 9.99, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: receipt_data }
                user.reload
                expect(user.user_settings.pro_subscription_expiration).to eq PurchaseReceipt.find_by(transaction_id: '70000458734964').expires_date
              end
            end
          end

          it 'skips product addition for most recent receipt if already processed' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: 9.99, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                # store initially
                post :new, { receipt: receipt_data }
                PurchaseReceipt.all.each{ |pr| pr.update_attributes(internal_status: PurchaseReceipt::STATUS_PROCESSED) }
                # now we POST again and expect no further action on user
                expect(subject).to_not receive(:add_product_for_user)
                post :new, { receipt: receipt_data }
              end
            end
          end
        end
      end
    end

    describe 'with subscription AND virtual currency product receipts' do
      let(:sample_payload) do
        JSON.parse(File.read(Rails.root.join('spec/fixtures/sample_receipt_w_virtual_currency_product.json')))
      end

      before(:each) do
        allow(PurchaseReceipt).to receive(:verify_ios_purchase).and_return(sample_payload)
      end

      describe 'no ProductType for apple_product_id in receipt' do
        it 'stores all receipts in [:latest_receipt_info] array and [:receipt][:in_app] - with price nil - even if no price supplied' do
          assert_enqueued_with(job: SentryJob) do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob) do
                post :new, { receipt: sample_payload[:latest_receipt] }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['70000458734964','310000293756518']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [false,true]
                expect(PurchaseReceipt.all.select{|pr| pr.transaction_id == '310000293756518'}.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [nil, nil]
              end
            end
          end
        end
      end

      describe 'with ProductType for apple_product_id in receipt' do
        before(:each) do
          Fabricate(:pro_subscription_product)
          Fabricate(:virtual_currency_small_product)
        end

        describe 'new_trial' do
          it 'stores all receipts in [:latest_receipt_info array] and [:receipt][:in_app] - with price from ProductType - even if no price supplied' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt] }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['70000458734964','310000293756518']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [false, true]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [9.99, 9.99]
              end
            end
          end

          it 'stores all receipts in [:latest_receipt_info array] and [:receipt][:in_app] even when price supplied' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt], price: price }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['70000458734964', '310000293756518']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [false, true]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [price, price]
              end
            end
          end

          it 'backfills subscription data previously seen but with missing data when storing all receipts in [:latest_receipt_info array] and [:receipt][:in_app]' do
            Fabricate(:purchase_receipt, user_id: user.id, transaction_id: sample_payload['latest_receipt_info'].first['transaction_id'], quantity: nil, expires_date: nil)
            receipt = PurchaseReceipt.find_by(transaction_id: sample_payload['latest_receipt_info'].first['transaction_id'])
            expect(receipt.quantity).to be nil
            expect(receipt.expires_date).to be nil
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt], price: price }
                receipt.reload
                expect(receipt.quantity).to eq sample_payload[:latest_receipt_info].first[:quantity].to_i
                expect(receipt.expires_date).to eq Time.zone.parse(sample_payload[:latest_receipt_info].first[:expires_date])
                expect(receipt.purchase_receipt_data.get_data).to eq sample_payload[:latest_receipt]
                expect(PurchaseReceipt.all.map{|r| r.price.to_f}).to eq [price, price]
              end
            end
          end

          it 'selects furthest expires_date from available receipts' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: receipt_data }
                user.reload
                expect(user.user_settings.pro_subscription_expiration).to eq PurchaseReceipt.find_by(transaction_id: '310000293756518').expires_date
              end
            end
          end

          it 'skips product addition for most recent receipt if already processed' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                # store initially
                post :new, { receipt: receipt_data }
                PurchaseReceipt.all.each{ |pr| pr.update_attributes(internal_status: PurchaseReceipt::STATUS_PROCESSED) }
                # now we POST again and expect no further action on user
                expect(subject).to_not receive(:add_product_for_user)
                post :new, { receipt: receipt_data }
              end
            end
          end

          it 'calls User#reset_post_allowed_interval! for user' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_new_trial], user.id, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                expect_any_instance_of(User).to receive(:reset_post_allowed_interval!)
                post :new, { receipt: receipt_data }
              end
            end
          end
        end

        describe 'paid' do
          before(:each) do
            sample_payload['latest_receipt_info'].each{ |r| r['is_trial_period'] = 'false' }
          end

          it 'stores all receipts in [:latest_receipt_info] array and [:receipt][:in_app] - with price from ProductType - even if no price supplied' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: 9.99, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt] }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['70000458734964', '310000293756518']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [false, false]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map{|r| r.price.to_f}).to eq [9.99, 9.99]
              end
            end
          end

          it 'stores all receipts in [:latest_receipt_info] array and [:receipt][:in_app] even when price supplied' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: price, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: sample_payload[:latest_receipt], price: price }
                expect(PurchaseReceipt.all.map(&:user)).to eq [user, user]
                expect(PurchaseReceipt.all.map(&:quantity)).to eq [1, 1]
                expect(PurchaseReceipt.all.map(&:transaction_id)).to eq ['70000458734964', '310000293756518']
                expect(PurchaseReceipt.all.map(&:is_trial_period?)).to eq [false, false]
                expect(PurchaseReceipt.all.map{ |pr| pr.purchase_receipt_data.get_data }).to eq [sample_payload[:latest_receipt], sample_payload[:latest_receipt]]
                expect(PurchaseReceipt.all.map(&:price)).to eq [price, price]
              end
            end
          end

          it 'selects furthest expires_date from available receipts' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: 9.99, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                post :new, { receipt: receipt_data }
                user.reload
                expect(user.user_settings.pro_subscription_expiration).to eq PurchaseReceipt.find_by(transaction_id: '310000293756518').expires_date
              end
            end
          end

          it 'skips product addition for most recent receipt if already processed' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: 9.99, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                # store initially
                post :new, { receipt: receipt_data }
                PurchaseReceipt.all.each{ |pr| pr.update_attributes(internal_status: PurchaseReceipt::STATUS_PROCESSED) }
                # now we POST again and expect no further action on user
                expect(subject).to_not receive(:add_product_for_user)
                post :new, { receipt: receipt_data }
              end
            end
          end

          it 'calls User#reset_post_allowed_interval! for user' do
            assert_enqueued_with(job: SendEventToCustomerIOJob) do
              assert_enqueued_with(job: SendEventToAdjustJob, args: [ADJUST_CONSTANTS[:event_renewal], user.id, price: 9.99, product_id: sample_payload['latest_receipt_info'].first['product_id']]) do
                expect_any_instance_of(User).to receive(:reset_post_allowed_interval!)
                post :new, { receipt: sample_payload[:latest_receipt] }
              end
            end
          end
        end
      end
    end
  end
end
