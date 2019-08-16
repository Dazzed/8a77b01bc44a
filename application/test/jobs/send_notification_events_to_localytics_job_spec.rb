# frozen_string_literal: true

require 'sidekiq/testing'

describe SendNotificationEventsToLocalyticsJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user) }
  let(:device) { Fabricate(:apn_device, user_id: user.id) }
  let(:message) { 'Test message' }
  let(:localytics_url) { 'https://analytics.localytics.com/events/v0/uploads' }

  before(:each) do
    ENV["LOCALYTICS_API_KEY"] = 'abc'
    ENV["LOCALYTICS_API_SECRET"] = '123'
    ENV["LOCALYTICS_APP_KEY"] = 'xyz'
    ENV["LOCALYTICS_API_EVENTS_URL"] = localytics_url
  end

  describe 'no APN::Notifications' do
    it 'does not send anything' do
      Sidekiq::Testing.inline! do
        expect_any_instance_of(Faraday::Connection).to_not receive(:post)
        SendNotificationEventsToLocalyticsJob.perform_now
      end
    end
  end

  describe 'with APN::Notifications' do
    let(:notification) {
      APN::Notification.create!(
        device: device,
        badge: 1,
        background: true,
        alert: message,
        sound: :default,
        notification_type: :new_message
      )
    }

    before(:each) do
      allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(Faraday::Response.new)
      allow_any_instance_of(Faraday::Response).to receive(:success?).and_return(true)
    end

    it 'does not send anything if APN::Notifications found but already sent' do
      notification.update_attributes(localytics_sent_at: Time.current)
      Sidekiq::Testing.inline! do
        expect_any_instance_of(Faraday::Connection).to_not receive(:post)
        SendNotificationEventsToLocalyticsJob.perform_now
      end
    end

    it 'deletes APN::Notification after processing' do
      notification # instantiate into existence
      Sidekiq::Testing.inline! do
        now = Time.current
        Timecop.freeze(now) do
          SendNotificationEventsToLocalyticsJob.perform_now
          expect(APN::Notification.all).to eq []
        end
      end
    end
  end
end
