# frozen_string_literal: true

Fabricator(:cohort) do
  name { sequence(:cohort_name) { |i| "CohortName#{i}" } }
  description { sequence(:cohort_description) { |i| "CohortDescription#{i}" } }
  data { { key: 'value' } }
end
