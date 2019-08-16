# frozen_string_literal: true

class SampleClass
  include PurchasesHelper
end

describe PurchasesHelper do
  let(:user) { Fabricate(:user) }
  let(:logger) { double('logger') }
  let(:sample_payload) do
    payload = JSON.parse(File.read(Rails.root.join('spec/fixtures/sample_receipt.json')))
    payload.deep_symbolize_keys!
  end

  before(:each) do
    allow(logger).to receive(:info).and_return(true)
    allow_any_instance_of(SampleClass).to receive(:current_user).and_return(user)
    allow_any_instance_of(SampleClass).to receive(:logger).and_return(logger)
  end

  # Placeholder spec, now that we refactored methods out of PurchasesHelper into PurchaseReceipt model
end
