    test "fails when an increasing sequence dips" do
      result =
        try do
          assert_monotonic([1, 5, 4, 9])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "increasing"
    end