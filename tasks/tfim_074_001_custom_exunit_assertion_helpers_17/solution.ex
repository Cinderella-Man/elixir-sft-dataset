    test "fails for a datetime in the future beyond tolerance" do
      future = apply(DateTime, :add, [DateTime.utc_now(), 30, :second])

      result =
        try do
          assert_recent(future, 5)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
    end