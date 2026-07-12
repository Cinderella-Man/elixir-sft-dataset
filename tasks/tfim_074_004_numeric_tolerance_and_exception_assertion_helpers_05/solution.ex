    test "fails for equal adjacent values (not strict)" do
      result =
        try do
          assert_monotonic([1, 2, 2, 3])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "index 1"
    end