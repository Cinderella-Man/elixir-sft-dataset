    test "failure for a decreasing sequence names the decreasing direction" do
      result =
        try do
          assert_monotonic([10, 3, 7, 1], :decreasing)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "decreasing"
      assert result =~ "index 1"
    end