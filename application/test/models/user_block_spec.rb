# frozen_string_literal: true

describe UserBlock, type: :model do
  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :user_id }
    it { expect(subject).to have_db_column :blocked_user_id }
    it { expect(subject).to have_db_column :block_flag }
    it { expect(subject).to have_db_column :reason_text }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'relationships' do
    it { expect(subject).to belong_to(:user) }
    it { expect(subject).to belong_to(:blocked_user) }
  end

  describe 'validations' do
    let(:user1) { Fabricate(:user) }
    let(:user2) { Fabricate(:user) }

    it { should validate_presence_of(:user) }
    it { should validate_presence_of(:blocked_user) }

    it 'does not allow blocking the same user twice for the same initiating user' do
      block = Fabricate(:user_block, user: user1, blocked_user: user2)
      new_block = Fabricate.build(:user_block, user: user1, blocked_user: user2)
      expect { new_block.save! }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Blocked user has already been taken')
    end

    describe 'block_flag' do
      it 'allows saving without' do
        expect {
          Fabricate(:user_block, user: user1, blocked_user: user2)
        }.to_not raise_error
      end

      it 'enforces a UserBlockFlags enum if provided' do
        expect {
          Fabricate(:user_block, user: user1, blocked_user: user2, block_flag: 555)
        }.to raise_error(ActiveRecord::RecordInvalid, 'Validation failed: Block flag must be one of UserBlockFlags: [1, 2, 3, 4, 5, 6]')
      end
    end
  end
end
