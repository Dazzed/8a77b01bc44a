# frozen_string_literal: true

require 'sidekiq/testing'

describe SendEventToAdjustJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user_with_location) }
  let(:user_settings) { user.user_settings }
  let(:event) { 'sample_event' }
  let(:revenue) { 7.99 }
  let(:product_id) { 'com.foundermark.Friended.test_product_id_1' }

  it 'sends to Sentry if UserSettings for user_id not found' do
    Sidekiq::Testing.inline! do
      assert_enqueued_with(job: SentryJob, args: [{ message: "Aborted sending to Adjust due to no UserSetting for user: 999999, event: #{event}" }]) do
        SendEventToAdjustJob.perform_now(event, 999_999)
      end
    end
  end

  it 'sends to Sentry if idfa or adid not found' do
    Sidekiq::Testing.inline! do
      assert_enqueued_with(job: SentryJob, args: [{ message: "Aborted sending to Adjust due to no idfa or adid. user: #{user.id}, event: #{event}" }]) do
        user_settings.update_attributes!(idfa: nil, adid: nil)
        SendEventToAdjustJob.perform_now(event, user.id)
      end
    end
  end

  it 'sends event payload to Adjust for a valid user with revenue' do
    allow_any_instance_of(Faraday::Connection).to receive(:post).with(ADJUST_CONSTANTS[:url], any_args).and_return(Faraday::Response.new)
    allow_any_instance_of(Faraday::Response).to receive(:success?).and_return(true)
    Sidekiq::Testing.inline! do
      SendEventToAdjustJob.perform_now(event, user.id, price: revenue)
    end
  end

  it 'sends event payload to Adjust for a valid user with revenue and product_id' do
    allow_any_instance_of(Faraday::Connection).to receive(:post).with(ADJUST_CONSTANTS[:url], any_args).and_return(Faraday::Response.new)
    allow_any_instance_of(Faraday::Response).to receive(:success?).and_return(true)
    Sidekiq::Testing.inline! do
      SendEventToAdjustJob.perform_now(event, user.id, price: revenue, product_id: product_id)
    end
  end

  it 'sends to Sentry if response from Adjust was unsuccessful' do
    allow_any_instance_of(Faraday::Connection).to receive(:post).with(ADJUST_CONSTANTS[:url], any_args).and_return(Faraday::Response.new)
    allow_any_instance_of(Faraday::Response).to receive(:success?).and_return(false)
    Sidekiq::Testing.inline! do
      assert_enqueued_with(job: SentryJob) do
        SendEventToAdjustJob.perform_now(event, user.id)
      end
    end
  end
end
