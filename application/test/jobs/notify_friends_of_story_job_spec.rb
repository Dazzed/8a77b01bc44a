# frozen_string_literal: true

require 'sidekiq/testing'

describe NotifyFriendsOfStoryJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user) }
  let(:friend) { Fabricate(:user) }
  let(:friend2) { Fabricate(:user) }

  before(:each) do
    user
    user.is_new = false
    friend
    friend.is_new = false
    friend2
    friend2.is_new = false
    user.last_active_at = Time.now
    friend.last_active_at = Time.now
    # create friendships
    friendship1 = Fabricate(:friendship, user: user, friend: friend)
    friendship1a = Fabricate(:friendship, user: friend, friend: user)
    friendship2 = Fabricate(:friendship, user: user, friend: friend2)
    friendship2a = Fabricate(:friendship, user: friend2, friend: user)
  end

  it 'triggers a SendAPNJob to your friends' do
    story = Fabricate(:friend_story, user: user)
    assert_enqueued_with(
      job: SendAPNJob) do
        Sidekiq::Testing.inline! do
          NotifyFriendsOfStoryJob.perform_now(story.id)
        end
    end
  end

end
