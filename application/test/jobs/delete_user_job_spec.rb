# frozen_string_literal: true

require 'sidekiq/testing'

describe DeleteUserJob, type: :job do
  include ActiveJob::TestHelper

  context 'location' do
    let(:user) { Fabricate(:user_with_location) }

    it 'deletes associated Location record' do
      expect(user.location.nil?).to be false
      Sidekiq::Testing.inline! do
        location_id = user.location.id
        DeleteUserJob.perform_now(user.id)
        expect(Location.find_by(id: location_id)).to be nil
      end
    end
  end
end
