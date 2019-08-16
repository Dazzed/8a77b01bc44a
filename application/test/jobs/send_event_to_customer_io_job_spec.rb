# frozen_string_literal: true

require 'customerio'
require 'sidekiq/testing'

describe SendEventToCustomerIOJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user_with_location) }
  let(:event) {
    {
      sample: 'event'
    }
  }
  let(:params) {
    {
      sample: 'params'
    }
  }

  it 'sends to Sentry if user_id not found' do
    Sidekiq::Testing.inline! do
      expect_any_instance_of(Customerio::Client).to receive(:track).with(999_999, event, params).and_return(true)
      SendEventToCustomerIOJob.perform_now(event, 999_999, params)
    end
  end

  it 'sends event payload to CustomerIO for a valid user with params' do
    # instantiate User
    user
    custom_payload = CustomerioForFriended.custom_payload(user)
    Sidekiq::Testing.inline! do
      expect_any_instance_of(Customerio::Client).to receive(:track).with(user.id, event, params.merge(custom_payload)).and_return(true)
      SendEventToCustomerIOJob.perform_now(event, user.id, params)
    end
  end
end
