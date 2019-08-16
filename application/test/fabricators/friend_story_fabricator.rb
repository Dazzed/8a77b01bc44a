Fabricator(:friend_story) do
  text { Faker::Lorem.sentence }
  external_media_url { Faker::Avatar.image }
end
