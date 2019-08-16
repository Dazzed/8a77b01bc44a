# frozen_string_literal: true

describe Rating do
  let(:user) { Fabricate(:user) }
  let(:post) { Fabricate(:post, user: user) }
  subject { Fabricate(:rating, user: user, target_id: post.id, target_type: 'post') }

  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :target_id }
    it { expect(subject).to have_db_column :target_type }
    it { expect(subject).to have_db_column :value }
    it { expect(subject).to have_db_column :rating_text }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:user) }
    it { expect(subject).to belong_to(:rated_posts) }
  end

  describe 'scopes' do
    it 'offers only retrieving recent ratings' do
      now = Time.current
      Timecop.freeze(now) do
        expect(Rating.recent.to_sql).to eq Rating.all.where('ratings.created_at > ?', now - CONSTANTS[:posts_feed_timebox_hours].hours).to_sql
      end
    end

    it 'offers retrieving only visible ratings' do
      expect(Rating.visible.to_sql).to eq Rating.joins(:user).where("users.hidden_reason IS NULL or users.hidden_reason = ''").to_sql
    end
  end
end
