require 'rails_helper'

describe Friendship, type: :model do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :friend_id }
    it { expect(subject).to have_db_column :status }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  context "relationships" do
    it { expect(subject).to belong_to(:user) }
    it { expect(subject).to belong_to(:friend) }
  end

  describe 'automatically sets status of friendship when requests are created' do
    user1 = Fabricate(:user)
    user2 = Fabricate(:user)

    it 'triggers check_and_accept_friendship on create' do
      friendship = Friendship.new(user: user1, friend: user2)
      expect(friendship).to receive(:check_and_accept_friendship)
      friendship.save
    end

    it 'triggers remove_request_and_unfriend on destroy' do
      friendship = Fabricate(:friendship, user: user1, friend: user2)
      expect(friendship).to receive(:remove_request_and_unfriend)
      friendship.destroy
    end

    it 'removes all related friendship rows on destroy' do
      friendship = Fabricate(:friendship, user: user1, friend: user2)
      expect(Friendship.all.count).to eq(1)
      friendship1 = Fabricate(:friendship, user: user2, friend: user1)
      expect(friendship1.status).to eq("accepted")
      expect(Friendship.all.count).to eq(2)
      friendship.destroy
      expect(Friendship.all.count).to eq(0)
    end

    it 'sets status to pending on the first friendship created' do
      friendship = Fabricate(:friendship, user: user1, friend: user2)
      expect(friendship.status).to eq "pending"
    end

    it 'sets status to accepted on the when friend also creates a friendship' do
      friendship = Friendship.create(user: user1, friend: user2)
      friendship_reciprocal = Friendship.create(user: user2, friend: user1)
      friendship = Friendship.find(friendship.id)  # get updated friendship
      expect(friendship_reciprocal.status).to eq "accepted"
      expect(friendship.status).to eq "accepted"
    end
  end

end
