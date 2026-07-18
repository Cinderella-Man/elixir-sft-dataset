  test "assert_next_message timeout failure shows the expected term and the wait" do
    result =
      try do
        assert_next_message(:never_arrives, 50)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    refute result == :no_failure
    assert result =~ ":never_arrives"
    assert result =~ "50"
  end