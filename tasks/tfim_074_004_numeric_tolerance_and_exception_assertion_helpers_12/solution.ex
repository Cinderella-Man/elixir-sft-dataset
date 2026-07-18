    test "fails when expected is zero but actual is not" do
      result =
        try do
          assert_within_pct(3, 0, 5)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
    end