    test "failure for equal adjacent values under :decreasing names that direction" do
      result =
        try do
          assert_monotonic([9, 4, 4], :decreasing)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "decreasing"
      assert result =~ "index 1"
    end