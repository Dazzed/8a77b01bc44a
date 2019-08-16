# frozen_string_literal: true

require 'sidekiq/testing'

describe SendAPNJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { Fabricate(:user) }
  let(:user2) { Fabricate(:user) }
  let(:message) { 'test notification' }

  it 'sends to user if only single provided' do
    Fabricate(:apn_device, user_id: user.id)
    expect_any_instance_of(Houston::Client).to receive(:push).and_return(true)
    Sidekiq::Testing.inline! do
      SendAPNJob.perform_now([user.id], { type: "new_message", message: 'message' })
    end
  end

  it 'sends to all users if multiple provided' do
    device1 = Fabricate(:apn_device, user_id: user.id)
    Fabricate(:apn_device, token: device1.token.gsub('a', 'b'), user_id: user2.id)
    expect_any_instance_of(Houston::Client).to receive(:push).twice.and_return(true)
    Sidekiq::Testing.inline! do
      SendAPNJob.perform_now([user.id, user2.id], { type: "new_message", message: 'message' })
    end
  end

  it 'sends to only known user if list includes unknown users' do
    Fabricate(:apn_device, user_id: user.id)
    expect_any_instance_of(Houston::Client).to receive(:push).once.and_return(true)
    Sidekiq::Testing.inline! do
      SendAPNJob.perform_now([user.id, 888_888], { type: "new_message", message: 'message' })
    end
  end

  it 'sends even with a long title' do
    Fabricate(:apn_device, user_id: user.id)
    expect_any_instance_of(Houston::Client).to receive(:push).once.and_return(true)
    Sidekiq::Testing.inline! do
      SendAPNJob.perform_now([user.id, 888_888], { type: "new_message", title: "Ziggzock: Yes it is Elena. And the type of intimacy that I'm talking about goes way way way beyond just getting to \"\"\"\" know \"\"\"\". Someone. The intimacy that IM. Talking about takes years and lots and lots and lots of conversations and time with that person. If ever you taste the true deep deep intimacy of heart of heart that IM Talking about. You will be very miserable if ever you loose it. Cause that element/ essence of heart is extremely extremely extremely difficult and very very very rare to find or achieve again ....... very very rare !!", "user_first_name"=>"Ziggzock", "user_profile_image_url"=>"https://foundermark-friended-photos.s3.amazonaws.com/uploads/user_photo/image/2479950/user_image.jpeg", "override_limit"=>true, "title"=>"Ziggzock: Yes it is Elena. And the type of intimacy that I'm talking about goes way way way beyond just getting to \"\"\"\" know \"\"\"\". Someone. The intimacy that IM. Talking about takes years and lots and lots and lots of conversations and time with that person. If ever you taste the true deep deep intimacy of heart of heart that IM Talking about. You will be very miserable if ever you loose it. Cause that element/ essence of heart is extremely extremely extremely difficult and very very very rare to find or achieve again ....... very very rare !!" })
    end
  end

  it 'does not send anything for list of unknown user ids' do
    device1 = Fabricate(:apn_device, user_id: user.id)
    Fabricate(:apn_device, token: device1.token.gsub('a', 'b'), user_id: user2.id)
    expect_any_instance_of(Houston::Client).to_not receive(:push)
    Sidekiq::Testing.inline! do
      SendAPNJob.perform_now([999_999, 888_888], { type: "new_message", message: 'message' })
    end
  end
end
