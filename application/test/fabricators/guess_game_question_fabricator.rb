Fabricator(:guess_game_question) do
  text "%@ is..."
  my_text "I am..."

  after_create do |question|
    2.times do
      Fabricate(:guess_game_choice, question: question)
    end
  end
end
