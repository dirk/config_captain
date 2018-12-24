require 'concurrent/atomic/thread_local_var'

class CaptainConfig::Service
  extend ActiveSupport::Autoload

  autoload :DSL

  # The statically-defined entries that this service should support.
  attr_reader :configured_entries

  # The keys and values read from the database (or defaults).
  attr_reader :configs

  def initialize(load_after_initialize: true, &block)
    @configured_entries = {}
    @configs = Concurrent::ThreadLocalVar.new(nil)

    DSL.new(self).instance_eval(&block)

    # Make the service immediately available after it's declared.
    load if load_after_initialize
  end

  def <<(configured_entry)
    @configured_entries[configured_entry.key] = configured_entry
  end

  def get(key)
    assert_loaded!

    configs.value.fetch key
  end

  def set(key, new_value)
    assert_loaded!

    record = configured_entries.fetch(key).model.find_or_create_by!(key: key)
    record.value = new_value
    record.save!

    # Read the value back out of the record because the model/record
    # is authoritative.
    authoritative_new_value = record.value
    configs.value[key] = authoritative_new_value
    authoritative_new_value
  end

  alias_method :[], :get
  alias_method :[]=, :set

  def loaded?
    !configs.value.nil?
  end

  # Load new values from the database (or default values from the
  # configured entries).
  def load
    new_configs = {}

    records = CaptainConfig::BaseConfig
      .where(keys: configured_entries.keys)
      .map { |record| [record.key.to_sym, record] }
      .to_hash

    configured_entries.each do |key, configured_entry|
      record = records[key]

      value = if record
        # Check that it's the type we're expecting.
        expected = record.klass
        actual = configured_entry.model
        if expected != actual
          raise(
            "Error loading #{key}: record class from database doesn't match " \
            "configured class (expected: #{expected}, got: #{actual})",
          )
        end
        record.value
      else
        configured_entry.default_value
      end

      new_configs[key] = value
    end

    @configs.value = new_configs
  end

  private

  def assert_loaded!
    raise 'Not loaded' unless loaded?
  end
end
