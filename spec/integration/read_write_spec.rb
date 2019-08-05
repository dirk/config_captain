require 'spec_helper'

RSpec.describe 'Integration' do
  include CaptainConfig::Shell

  around(:all) do |all|
    Dir.chdir('spec/sample') do
      shell 'sqlite3 db/development.sqlite3 "DELETE FROM captain_configs;"'

      env = {
        BUNDLE_GEMFILE: nil,
        RAILS_ENV: 'development',
      }
      if ENV['CI'] == 'true'
        env[:BUNDLE_PATH] = nil
        env[:GEM_HOME] = nil
        env[:GEM_PATH] = nil
      end

      WaitForIt.new(
        'bundle exec puma',
        env: env,
        wait_for: 'Listening on',
      ) do
        all.run
      end
    end
  end

  let(:host) { 'http://localhost:3000' }

  it 'reads and writes values' do
    # It should start off as false.
    expect(HTTParty.get("#{host}/configs/some_boolean").body).to eq 'false'

    # Then set it to true.
    expect(
      HTTParty.patch(
        "#{host}/configs/some_boolean",
        body: { value: 'true' },
      ).body,
    ).to eq 'true'

    # And it should still be true.
    expect(HTTParty.get("#{host}/configs/some_boolean").body).to eq 'true'
  end
end
