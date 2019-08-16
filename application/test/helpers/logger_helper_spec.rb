# frozen_string_literal: true

class SampleClass
  include LoggingHelper

  def instance_method
    logger.tagged(self.class.inspect) do
      logger.debug('pre logic')
      a = *(1..10)
      a.sort
      logger.debug('post logic')
    end
  end

  def self.class_method
    logger.tagged(self.inspect) do
      logger.debug('pre logic')
      a = *(1..10)
      a.sort
      logger.debug('post logic')
    end
  end
end

describe LoggingHelper do
  it 'instance method calls logger methods just fine' do
    expect { SampleClass.new.instance_method }.to_not raise_error
  end

  it 'class method calls logger methods just fine' do
    expect { SampleClass.class_method }.to_not raise_error
  end
end
