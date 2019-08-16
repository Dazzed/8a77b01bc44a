# frozen_string_literal: true

Fabricator(:token) do
  hashed_access_token nil
  hashed_refresh_token nil
  expires_on nil
  refresh_by nil
  provider nil
end
