require 'spec_helper'
require 'sidekiq/testing'

describe "Push" do
  include ActiveJob::TestHelper
  let(:user) { Fabricate(:user) }
  let(:headers) {
    {
      'HTTP_ACCEPT' => 'application/json',
      'ACCEPT' => 'application/json',
      'CONTENT_TYPE' => 'application/json'
    }
  }

  before(:each) do
    user
    user.is_new = false
    ENV["PUSH_API_TOKEN"] = "12345"
  end

  it 'returns 403 fails to send if push api token is not correct' do
    ActiveJob::Base.queue_adapter = :test
    expect {
      post "/push", {token: "test", id: user.id, title: "title", subtitle: "subtitle", body: "body"}.to_json, headers
      expect(response.status).to eq 403
    }.not_to have_enqueued_job(SendAPNJob)
  end

  it 'returns 200 and initiates SendAPNJob ' do
    ActiveJob::Base.queue_adapter = :test
    assert_enqueued_with(job: SendAPNJob) do
      post "/push", {token: "12345", id: user.id, title: "title", subtitle: "subtitle", body: "body"}.to_json, headers
      expect(response.status).to eq 200
    end
  end

end
