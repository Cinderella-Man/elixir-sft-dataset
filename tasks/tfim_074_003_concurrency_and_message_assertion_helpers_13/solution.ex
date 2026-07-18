    test "fails when no message arrives before the timeout" do
      result =
        try do
          assert_next_message(:never, 50)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "timed out" or result =~ "50"
    end