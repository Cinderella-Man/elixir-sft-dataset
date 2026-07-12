    test "fails when function never returns truthy within timeout" do
      result =
        try do
          assert_eventually(fn -> false end, 100, 20)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "timed out" or result =~ "timeout" or result =~ "100"
    end