# frozen_string_literal: true

describe UserSetting do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :purchased_posts_used }
    it { expect(subject).to have_db_column :purchased_post_count }
    it { expect(subject).to have_db_column :new_message_push }
    it { expect(subject).to have_db_column :new_post_reply_push }
    it { expect(subject).to have_db_column :inactive_push }
    it { expect(subject).to have_db_column :inactive_unread_push }
    it { expect(subject).to have_db_column :profile_view_push }
    it { expect(subject).to have_db_column :last_viewed_profile_views }
    it { expect(subject).to have_db_column :pro_subscription_expiration }
    it { expect(subject).to have_db_column :pro_subscription_start }
    it { expect(subject).to have_db_column :new_friend_requests_push }
    it { expect(subject).to have_db_column :new_friend_stories_push }
    it { expect(subject).to have_db_column :feed_filter_max }
    it { expect(subject).to have_db_column :feed_filter_min }
    it { expect(subject).to have_db_column :idfa }
    it { expect(subject).to have_db_column :adid }
    it { expect(subject).to have_db_column :last_subscription_purchase_id }
    it { expect(subject).to have_db_column :subscription_state }
    it { expect(subject).to have_db_column :initial_trial_subscription_days }
    it { expect(subject).to have_db_column :location_type }
    it { expect(subject).to have_db_column :num_dob_updates }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:user) }
    it { expect(subject).to belong_to(:cohort) }
  end

  describe 'serializable_hash' do
    let(:user) { Fabricate.create(:user) }
    let(:cohort) {
      Fabricate.create(:product_type, paywall: true, referral: true)
      Fabricate.create(
        :cohort,
        name: CONFIG[:override_all_subscriptions] ? "NoPaywall" : ProductType.paywall.first.apple_product_id,
        description: 'Initial cohort',
        active: true,
        data: { onboard_trial_active: CONFIG[:onboard_trial_active], override_all_subscriptions: CONFIG[:override_all_subscriptions] },
        paywall: ProductType.paywall.first,
        referral: ProductType.referral.first,
        tiers: ProductType.tiers
      )
    }

    it 'creates proper json result' do
      user_setting = Fabricate.create(:user_setting, user: user, cohort: cohort)
      result = user_setting.as_json
      expect(result['cohort_data']).to eq cohort.as_json
    end
  end
end
