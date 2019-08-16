# frozen_string_literal: true

require 'sidekiq/testing'

describe StatusUpdateJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user_with_location) }
  let(:user_settings) { user.user_settings }
  let(:sample_status_update) do
    payload = JSON.parse(File.read(Rails.root.join('spec/fixtures/sample_status_update.json')))
    payload.deep_symbolize_keys!
  end

  before(:each) do
    stub_request(:put, /foundermark-friended-dev.s3.amazonaws.com/)
      .to_return(status: 200, body: "stubbed response", headers:{"Etag": nil})
  end

  describe 'tracking events for user' do
    it 'does not track user if no latest receipt found' do
      sample_status_update[:latest_receipt_info] = nil
      expect_any_instance_of(User).to_not receive(:track_user)
      StatusUpdateJob.perform_now(sample_status_update)
    end

    it 'does not track user if no expires_date_formatted on latest receipt' do
      sample_status_update[:latest_receipt_info][:expires_date_formatted] = nil
      expect_any_instance_of(User).to_not receive(:track_user)
      StatusUpdateJob.perform_now(sample_status_update)
    end

    it 'does not track user if no original transaction id' do
      sample_status_update[:latest_receipt_info][:original_transaction_id] = nil
      expect_any_instance_of(User).to_not receive(:track_user)
      StatusUpdateJob.perform_now(sample_status_update)
    end

    it 'does not track user if no user for original transaction' do
      Fabricate(:purchase_receipt, transaction_id: sample_status_update[:latest_receipt_info][:original_transaction_id])
      expect_any_instance_of(User).to_not receive(:track_user)
      StatusUpdateJob.perform_now(sample_status_update)
    end

    it 'does not track user if product_id not :pro_subscription' do
      Fabricate(:purchase_receipt, user_id: user.id, transaction_id: sample_status_update[:latest_receipt_info][:original_transaction_id])
      sample_status_update[:latest_receipt_info][:product_id] = nil
      expect_any_instance_of(User).to_not receive(:track_user)
      StatusUpdateJob.perform_now(sample_status_update)
    end

    it 'tracks user if any notification_type provided' do
      Fabricate(:purchase_receipt, user_id: user.id, transaction_id: sample_status_update[:latest_receipt_info][:original_transaction_id])
      sample_status_update[:notification_type] = 'BLAHBLAH'
      expect_any_instance_of(User).to receive(:track_user).and_return(true)
      StatusUpdateJob.perform_now(sample_status_update)
    end
  end

  describe 'CANCEL' do
    before(:each) do
      sample_status_update[:notification_type] = 'CANCEL'
      Fabricate(:purchase_receipt, user_id: user.id, transaction_id: sample_status_update[:latest_receipt_info][:original_transaction_id])
      latest_receipt_info = sample_status_update.delete(:latest_receipt_info)
      sample_status_update[:latest_expired_receipt_info] = latest_receipt_info
    end

    it 'sets subscription_state to cancelled' do
      assert_enqueued_with(job: SendEventToCustomerIOJob) do
        assert_enqueued_with(job: SendEventToAdjustJob) do
          StatusUpdateJob.perform_now(sample_status_update)
          user.reload
          expect(user_settings.subscription_state).to eq 'cancelled'
        end
      end
    end

    it 'sends events to Adjust & Customer IO & Branch' do
      assert_enqueued_with(job: SendEventToCustomerIOJob) do
        assert_enqueued_with(job: SendEventToAdjustJob) do
          assert_enqueued_with(job: SendEventToBranchJob) do
            StatusUpdateJob.perform_now(sample_status_update)
          end
        end
      end
    end

    it 'sends events to Adjust & Customer IO & Branch even if user is deleted' do
      user.destroy
      assert_enqueued_with(job: SendEventToCustomerIOJob) do
        assert_enqueued_with(job: SendEventToAdjustJob) do
          assert_enqueued_with(job: SendEventToBranchJob) do
            StatusUpdateJob.perform_now(sample_status_update)
          end
        end
      end
    end
  end

  describe 'RENEWAL/INTERACTIVE_RENEWAL' do
    let(:price) { 4.99 }
    let(:original_receipt) { Fabricate(:purchase_receipt, user_id: user.id, transaction_id: sample_status_update[:latest_receipt_info][:original_transaction_id], price: price) }
    let(:sample_payload) do
      JSON.parse(File.read(Rails.root.join('spec/fixtures/sample_receipt.json')))
    end

    before(:each) do
      sample_status_update[:notification_type] = 'RENEWAL'
      original_receipt
      allow(PurchaseReceipt).to receive(:verify_ios_purchase).and_return(sample_payload)
    end

    describe 'receipt not yet processed' do
      it 'sets subscription_state to trial for is_trial_period = true' do
        assert_enqueued_with(job: SendEventToCustomerIOJob) do
          assert_enqueued_with(job: SendEventToAdjustJob) do
            StatusUpdateJob.perform_now(sample_status_update)
            user.reload
            expect(user_settings.subscription_state).to eq 'trial'
            sample_receipt = sample_payload[:latest_receipt_info].last
            expect(user_settings.pro_subscription_expiration).to eq Time.zone.parse(sample_receipt[:expires_date])
            expect(user.latest_subscription_price).to eq price
          end
        end
      end

      it 'sets subscription_state to paid for is_trial_period = false' do
        allow(PurchaseReceipt).to receive(:verify_ios_purchase).and_return(sample_payload.tap{ |p| p['latest_receipt_info'].each{ |r| r['is_trial_period'] = 'false' } })
        sample_status_update[:latest_receipt_info][:is_trial_period] = 'false'
        assert_enqueued_with(job: SendEventToCustomerIOJob) do
          assert_enqueued_with(job: SendEventToAdjustJob) do
            assert_enqueued_with(job: SendPurchaseToBranchJob) do
              assert_enqueued_with(job: SendEventToLocalyticsJob) do
                StatusUpdateJob.perform_now(sample_status_update)
                user.reload
                expect(user_settings.subscription_state).to eq 'paid'
                sample_receipt = sample_payload[:latest_receipt_info].last
                expect(user_settings.pro_subscription_expiration).to eq Time.zone.parse(sample_receipt[:expires_date])
                expect(user.latest_subscription_price).to eq price
              end
            end
          end
        end
      end

      it 'creates PurchaseReceipt with all relevant data for any receipt not previously seen' do
        assert_enqueued_with(job: SendEventToCustomerIOJob) do
          assert_enqueued_with(job: SendEventToAdjustJob) do
            StatusUpdateJob.perform_now(sample_status_update)
            sample_receipt = sample_payload[:latest_receipt_info].first
            receipt = PurchaseReceipt.find_by(transaction_id: sample_receipt[:transaction_id])
            expect(receipt.quantity).to eq sample_receipt[:quantity].to_i
            expect(receipt.expires_date).to eq Time.zone.parse(sample_receipt[:expires_date])
            expect(receipt.purchase_date).to eq Time.zone.parse(sample_receipt[:purchase_date])
            expect(receipt.original_purchase_date).to eq Time.zone.parse(sample_receipt[:original_purchase_date])
            expect(receipt.web_order_line_item_id).to eq sample_receipt[:web_order_line_item_id]
            expect(receipt.internal_status).to eq 'processed'
            expect(receipt.price).to eq original_receipt.price
          end
        end
      end

      it 'sends events to Adjust & Customer IO & Branch & Localytics' do
        sample_payload["latest_receipt_info"][0]["is_trial_period"] = "false"
        assert_enqueued_with(job: SendEventToCustomerIOJob) do
          assert_enqueued_with(job: SendEventToAdjustJob) do
            assert_enqueued_with(job: SendPurchaseToBranchJob) do
              assert_enqueued_with(job: SendEventToLocalyticsJob) do
                StatusUpdateJob.perform_now(sample_status_update)
              end
            end
          end
        end
      end

      it 'sends events to Adjust & Customer IO & Branch & Localytics even if User is destroyed' do
        sample_payload["latest_receipt_info"][0]["is_trial_period"] = "false"
        user.destroy
        assert_enqueued_with(job: SendEventToCustomerIOJob) do
          assert_enqueued_with(job: SendEventToAdjustJob) do
            assert_enqueued_with(job: SendPurchaseToBranchJob) do
              assert_enqueued_with(job: SendEventToLocalyticsJob) do
                StatusUpdateJob.perform_now(sample_status_update)
              end
            end
          end
        end
      end
    end

    describe 'receipt already processed' do
      before(:each) do
        Fabricate(:purchase_receipt, user_id: user.id, transaction_id: sample_status_update[:latest_receipt_info][:transaction_id], quantity: nil, expires_date: nil)
      end

      it 'sets subscription_state to trial for is_trial_period = true' do
        StatusUpdateJob.perform_now(sample_status_update)
        user.reload
        expect(user_settings.subscription_state).to eq 'trial'
      end

      it 'sets subscription_state to paid for is_trial_period = false' do
        sample_status_update[:latest_receipt_info][:is_trial_period] = 'false'
        StatusUpdateJob.perform_now(sample_status_update)
        user.reload
        expect(user_settings.subscription_state).to eq 'paid'
      end

      it 'updates existing PurchaseReceipt with fields in update payload' do
        StatusUpdateJob.perform_now(sample_status_update)
        receipt = PurchaseReceipt.find_by(transaction_id: sample_status_update[:latest_receipt_info][:transaction_id])
        expect(receipt.quantity).to eq sample_status_update[:latest_receipt_info][:quantity].to_i
        expect(receipt.expires_date).to eq Time.zone.parse(sample_status_update[:latest_receipt_info][:expires_date_formatted])
        expect(receipt.purchase_date).to eq Time.zone.parse(sample_status_update[:latest_receipt_info][:purchase_date])
        expect(receipt.original_purchase_date).to eq Time.zone.parse(sample_status_update[:latest_receipt_info][:original_purchase_date])
        expect(receipt.web_order_line_item_id).to eq sample_status_update[:latest_receipt_info][:web_order_line_item_id]
        expect(receipt.internal_status).to eq 'processed'
      end
    end
  end
end
