# frozen_string_literal: true

describe PostFilter do
  subject { Fabricate(:post_filter) }

  describe 'db columns' do
    it { expect(subject).to have_db_column :id }
    it { expect(subject).to have_db_column :term }
    it { expect(subject).to have_db_column :created_at }
    it { expect(subject).to have_db_column :updated_at }
  end

  describe 'validations' do
    it { should validate_uniqueness_of(:term) }
  end

  describe 'matches?' do
    before(:each) do
      Fabricate(:post_filter, term: 'abcdef')
      Fabricate(:post_filter, term: 'ghijkl')
      Fabricate(:post_filter, term: 'ghijklmno')
    end

    it 'reports false if no match among terms' do
      expect(PostFilter.matches?('xyz')).to be false
    end

    it 'reports false if text is subset of terms' do
      expect(PostFilter.matches?('abc')).to be false
    end

    it 'reports true for just one term exact match' do
      expect(PostFilter.matches?('abcdef')).to be true
    end

    it 'reports true for just one term exact match, case insensitive' do
      expect(PostFilter.matches?('abCDef')).to be true
    end

    it 'reports true for just one term partial match' do
      expect(PostFilter.matches?('123 abcdef 456')).to be true
    end

    it 'reports true for just one term partial match, case insensitive' do
      expect(PostFilter.matches?('123 abCDef 456')).to be true
    end

    it 'reports true for exact match among multiple terms' do
      expect(PostFilter.matches?('abcdef ghijkl')).to be true
    end

    it 'reports true for partial match among multiple terms' do
      expect(PostFilter.matches?('ghijkl')).to be true
    end
  end
end
