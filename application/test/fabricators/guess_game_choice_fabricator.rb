Fabricator(:guess_game_choice) do
  text { Faker::Hipster.word }
  my_text { "my #{Faker::Hipster.word}" }
end
