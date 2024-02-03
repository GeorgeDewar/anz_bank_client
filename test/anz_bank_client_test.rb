# frozen_string_literal: true

require "test_helper"
require "table_print"

class AnzBankClientTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::AnzBankClient::VERSION
  end
end
