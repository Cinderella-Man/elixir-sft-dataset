  test "assert_next_message waits the documented default of 1000ms and reports it" do
    result =
      try do
        assert_next_message(:never)
        :no_failure
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    refute result == :no_failure
    assert result =~ "1000"
  end