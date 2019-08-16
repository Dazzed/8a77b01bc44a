# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../../config/environment', __FILE__)
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!

require 'shoulda/matchers'
require 'database_cleaner'
require 'rspec_candy/all'
require 'rspec/json_expectations'
require 'webmock/rspec'
Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }

ActiveSupport::JSON::Encoding.time_precision = 0

def valid_on_create?
  errors.clear
  run_callbacks(:validate_on_create)
  validate_on_create
  errors.empty?
end

RSpec.configure do |config|
  config.before(:all) do
    DatabaseCleaner.clean_with :truncation
    Rails.application.load_seed
  end

  config.global_fixtures = :all

  # Bullet
  config.before(:each) do
    Bullet.start_request
  end

  config.after(:each) do
    Bullet.perform_out_of_channel_notifications if Bullet.notification?
    Bullet.end_request
  end

  config.include SplitHelper
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

