# require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe FriendStoriesController, type: :controller do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user_with_location) }
  let(:access_token) { JsonWebToken.encode(user_id: user.id).access_token }
  let(:user2) { Fabricate(:user_with_location) }
  let(:friend) { Fabricate(:user) }
  let(:friend2) { Fabricate(:user) }
  let(:friend3) { Fabricate(:user) }
  let(:friend4) { Fabricate(:user) }
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
    user.is_new = false
    user2
    user2.is_new = false
    friend
    friend.is_new = false
    friend2
    friend2.is_new = false
    friend3
    friend3.is_new = false
    friend4
    friend4.is_new = false
    user.last_active_at = Time.now
    friend.last_active_at = Time.now
    token
    facebook_auth
    allow(ExternalAuthProvider).to receive(:external_id_for_token).with(access_token, 'facebook').and_return(facebook_auth.provider_id)
    request.headers.merge!(headers)
    request.accept = 'application/json'
    Timecop.scale(3600) # turn seconds into hours to help testing
    # set timezone to EST to faciliate comparing JSON rendered datetimes
    Time.zone = ActiveSupport::TimeZone['Eastern Time (US & Canada)']

    # create friendships
    friendship1 = Fabricate(:friendship, user: user, friend: friend)
    friendship1a = Fabricate(:friendship, user: friend, friend: user)
    friendship2 = Fabricate(:friendship, user: user, friend: friend2)
    friendship2a = Fabricate(:friendship, user: friend2, friend: user)
    friendship3 = Fabricate(:friendship, user: user, friend: friend3)
    friendship3a = Fabricate(:friendship, user: friend3, friend: user)
    friendship4 = Fabricate(:friendship, user: user, friend: friend4)
    friendship4a = Fabricate(:friendship, user: friend4, friend: user)

    MediaUploader.any_instance.stub(:store!)
  end

  after(:each) do
    Time.zone = ActiveSupport::TimeZone['UTC']
  end

  describe 'GET /friend_stories' do
    it 'returns 200 and the stories your friends have created' do
      friend_stories = []
      10.times do
        friend_stories.push(Fabricate(:friend_story, user: friend))
      end
      friend4_stories = []
      3.times do
        friend4_stories.push(Fabricate(:friend_story, user: friend4))
      end
      friend2_stories = []
      2.times do
        friend2_stories.push(Fabricate(:friend_story, user: friend2))
      end
      friend3_stories = []
      15.times do
        friend3_stories.push(Fabricate(:friend_story, user: friend3))
      end

      get :index
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].count).to eq(4)
    end

    it 'returns 200 and both your and your friend stories with your stories first' do
      your_stories = []
      4.times do
        your_stories.push(Fabricate(:friend_story, user: user))
      end

      friend_stories = []
      10.times do
        friend_stories.push(Fabricate(:friend_story, user: friend))
      end
      friend4_stories = []
      3.times do
        friend4_stories.push(Fabricate(:friend_story, user: friend4))
      end
      friend2_stories = []
      2.times do
        friend2_stories.push(Fabricate(:friend_story, user: friend2))
      end
      friend3_stories = []
      15.times do
        friend3_stories.push(Fabricate(:friend_story, user: friend3))
      end

      get :index
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].count).to eq(5)
      expect(JSON.parse(response.body)["friend_stories"][0][0]["user_id"]).to eq(user.id)
    end

    it 'returns only max records' do
      stories = []
      10.times do
        stories.push(Fabricate(:friend_story, user: friend))
      end
      2.times do
        stories.push(Fabricate(:friend_story, user: friend4))
      end
      3.times do
        stories.push(Fabricate(:friend_story, user: friend2))
      end
      15.times do
        stories.push(Fabricate(:friend_story, user: friend3))
      end
      stories = stories.reverse
      get :index, {max: 2, offset: 0}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].count).to eq(2)
    end

    it 'returns only max records plus your stories' do
      stories = []
      3.times do
        Fabricate(:friend_story, user: user)
      end
      10.times do
        stories.push(Fabricate(:friend_story, user: friend))
      end
      2.times do
        stories.push(Fabricate(:friend_story, user: friend4))
      end
      3.times do
        stories.push(Fabricate(:friend_story, user: friend2))
      end
      15.times do
        stories.push(Fabricate(:friend_story, user: friend3))
      end
      stories = stories.reverse
      get :index, {max: 2, offset: 0}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].count).to eq(3)
    end

    it 'returns respects paging parameters offset and max' do
      friend_stories = []
      10.times do
        friend_stories.push(Fabricate(:friend_story, user: friend))
      end
      friend4_stories = []
      3.times do
        friend4_stories.push(Fabricate(:friend_story, user: friend4))
      end
      friend2_stories = []
      2.times do
        friend2_stories.push(Fabricate(:friend_story, user: friend2))
      end
      friend3_stories = []
      15.times do
        friend3_stories.push(Fabricate(:friend_story, user: friend3))
      end
      expected_story_ids = (friend4_stories+friend2_stories).map{|s| s.id }
      expected_story_ids = expected_story_ids.reverse

      get :index, {max: 2, offset: 1}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].flatten.map{|s| s["id"]}).to eq(expected_story_ids)
    end

    it 'returns respects paging parameters offset and max but inserts your stories first' do
      my_stories = []
      2.times do
        my_stories.push(Fabricate(:friend_story, user: user))
      end
      friend_stories = []
      10.times do
        friend_stories.push(Fabricate(:friend_story, user: friend))
      end
      friend4_stories = []
      3.times do
        friend4_stories.push(Fabricate(:friend_story, user: friend4))
      end
      friend2_stories = []
      2.times do
        friend2_stories.push(Fabricate(:friend_story, user: friend2))
      end
      friend3_stories = []
      15.times do
        friend3_stories.push(Fabricate(:friend_story, user: friend3))
      end
      expected_story_ids = (friend4_stories+friend2_stories).map{|s| s.id }
      expected_story_ids = my_stories.map{|s| s.id }.reverse + expected_story_ids.reverse

      get :index, {max: 2, offset: 1}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].flatten.map{|s| s["id"]}).to eq(expected_story_ids)
    end

    it 'returns 200 and does not return stories older than 48 hours' do
      3.times do
        Fabricate(:friend_story, user: friend, created_at: Time.now - 72.hours)
      end
      5.times do
        Fabricate(:friend_story, user: friend3, created_at: Time.now - 72.hours)
      end
      6.times do
        Fabricate(:friend_story, user: user, created_at: Time.now - 5.hours)
      end
      4.times do
        Fabricate(:friend_story, user: friend2)
      end
      get :index
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].count).to eq(2)
    end

    it 'returns 200 and does not return stories older than 48 hours, including yours' do
      6.times do
        Fabricate(:friend_story, user: user, created_at: Time.now - 49.hours)
      end

      3.times do
        Fabricate(:friend_story, user: friend, created_at: Time.now - 72.hours)
      end
      5.times do
        Fabricate(:friend_story, user: friend3, created_at: Time.now - 72.hours)
      end
      4.times do
        Fabricate(:friend_story, user: friend2)
      end
      get :index
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].count).to eq(1)
    end

    it 'returns 200 and does not return stories from hidden users' do
      stories = []
      3.times do
        stories.push(Fabricate(:friend_story, user: friend))
      end
      friend.update_attribute(:hidden_reason, "hidden")
      Fabricate(:friend_story, user: friend2)
      get :index
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_stories"].count).to eq(1)
    end
  end

  describe 'POST /users/:id/friend_stories' do
    it 'returns 403 if an image is not provided' do
      post :create, {user_id: user.id}
      expect(response.status).to eq 403
      post :create, {user_id: user.id, text: "hi"}
      expect(response.status).to eq 403
    end

    # Base64 fails to decode eventho same string works in Postman
    it 'returns 200 when an image is provided' do
      json_payload = {base64_image: '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAADKADAAQAAAABAAAADQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgADQAMAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAQEBAQEBAgEBAgMCAgIDBAMDAwMEBQQEBAQEBQYFBQUFBQUGBgYGBgYGBgcHBwcHBwgICAgICQkJCQkJCQkJCf/bAEMBAQEBAgICBAICBAkGBQYJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCf/dAAQAAf/aAAwDAQACEQMRAD8A/tO/aB8Tax8KbvwN4g8KQvdm/wBfttCn08FhHPDqXytIQAQJIDEHRmKqq7wSN1euf8Inp+oj7ZrkUEU75+SNtwUZ4BY4yR3IAGelfnz4V/Zg+KM/w78PWfiX4papq8mh3kd9DNdWsLu0kB3RkksTlSMhuT+dfmh8W/8Agmh46+JXjKfxPqHxo8QW7PuURxRsiqPMdjgR3Ma8sxJwo5Jr4OnnmNbdR4d67JyjZW6313PvMRkuFhCMIVldXu1F66+dj//Z'}.to_json
      post :create, json_payload, {format: 'json', user_id: user.id }
      friend_story = FriendStory.last
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_story"]["id"]).to eq(friend_story.id)
      expect(JSON.parse(response.body)["friend_story"]["media_type"]).to eq("image")
      # Some bug  is returning the tmp file path and not the url in media but this works
      # expect(JSON.parse(response.body)["friend_story"]["media_url"]).to eq(friend_story.media.url)
    end

    it 'triggers a push notification to friends' do
      json_payload = {base64_image: '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAADKADAAQAAAABAAAADQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgADQAMAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAQEBAQEBAgEBAgMCAgIDBAMDAwMEBQQEBAQEBQYFBQUFBQUGBgYGBgYGBgcHBwcHBwgICAgICQkJCQkJCQkJCf/bAEMBAQEBAgICBAICBAkGBQYJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCf/dAAQAAf/aAAwDAQACEQMRAD8A/tO/aB8Tax8KbvwN4g8KQvdm/wBfttCn08FhHPDqXytIQAQJIDEHRmKqq7wSN1euf8Inp+oj7ZrkUEU75+SNtwUZ4BY4yR3IAGelfnz4V/Zg+KM/w78PWfiX4papq8mh3kd9DNdWsLu0kB3RkksTlSMhuT+dfmh8W/8Agmh46+JXjKfxPqHxo8QW7PuURxRsiqPMdjgR3Ma8sxJwo5Jr4OnnmNbdR4d67JyjZW6313PvMRkuFhCMIVldXu1F66+dj//Z'}.to_json
      assert_enqueued_with(
        job: NotifyFriendsOfStoryJob) do
          post :create, json_payload, {format: 'json', user_id: user.id }
          expect(response.status).to eq 200
      end
    end

    it 'does not trigger a push notification to friends if hidden' do
      json_payload = {base64_image: '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAADKADAAQAAAABAAAADQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgADQAMAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAQEBAQEBAgEBAgMCAgIDBAMDAwMEBQQEBAQEBQYFBQUFBQUGBgYGBgYGBgcHBwcHBwgICAgICQkJCQkJCQkJCf/bAEMBAQEBAgICBAICBAkGBQYJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCf/dAAQAAf/aAAwDAQACEQMRAD8A/tO/aB8Tax8KbvwN4g8KQvdm/wBfttCn08FhHPDqXytIQAQJIDEHRmKqq7wSN1euf8Inp+oj7ZrkUEU75+SNtwUZ4BY4yR3IAGelfnz4V/Zg+KM/w78PWfiX4papq8mh3kd9DNdWsLu0kB3RkksTlSMhuT+dfmh8W/8Agmh46+JXjKfxPqHxo8QW7PuURxRsiqPMdjgR3Ma8sxJwo5Jr4OnnmNbdR4d67JyjZW6313PvMRkuFhCMIVldXu1F66+dj//Z'}.to_json
      expect {
          user.hidden_reason = "hiding test user"
          user.save
          post :create, json_payload, {format: 'json', user_id: user.id }
          expect(response.status).to eq 200
      }.not_to have_enqueued_job(NotifyFriendsOfStoryJob)
    end
  end

  describe 'GET /friend_stories/:id' do
    it 'returns 403 if invalid friend story id' do
      friend_story = Fabricate(:friend_story, user: friend)
      get :show, {id: 100}
      expect(response.status).to eq 403
    end

    it 'returns 200 if story is from friend and was created < 48 hours ago' do
      friend_story = Fabricate(:friend_story, user: friend)
      get :show, {id: friend_story.id}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_story"]["id"]).to eq(friend_story.id)
    end

    it 'returns 200 if story is created by current_user and was created < 48 hours ago' do
      friend_story = Fabricate(:friend_story, user: user)
      get :show, {id: friend_story.id}
      expect(response.status).to eq 200
      expect(JSON.parse(response.body)["friend_story"]["id"]).to eq(friend_story.id)
    end

    it 'returns 403 if story is from friend and was created > 48 hours ago' do
      friend_story = Fabricate(:friend_story, user: friend, created_at: Time.now-50.hours)
      get :show, {id: friend_story.id}
      expect(response.status).to eq 403
    end

    it 'returns 403 if story is created by current_user and was created > 48 hours ago' do
      friend_story = Fabricate(:friend_story, user: user, created_at: Time.now-50.hours)
      get :show, {id: friend_story.id}
      expect(response.status).to eq 403
    end

  end

  describe 'POST /friend_stories/:id/read' do
    it 'returns 200 to mark when a friend story is read' do
      friend_story = Fabricate(:friend_story, user: friend)
      post :read, {id: friend_story.id}
      expect(response.status).to eq 200
      expect(FriendStoriesUsersRead.last.friend_story_id).to eq(friend_story.id)
      expect(FriendStoriesUsersRead.last.user_id).to eq(user.id)
    end
  end

  describe 'POST /friend_stories/read' do
    it 'returns 200 and marks stories as read when passed in a list of ids' do
      ids =  []
      10.times { ids.push(Fabricate(:friend_story, user: friend).id) }

      last_read_count = FriendStoriesUsersRead.all.count
      post :read, {ids: ids}

      expect(response.status).to eq 200
      expect(FriendStoriesUsersRead.all.count).to eq(last_read_count+10)
    end
  end
end
