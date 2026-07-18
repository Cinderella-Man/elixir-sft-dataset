    test "fails for a datetime well in the past" do
      old = apply(DateTime, :add, [DateTime.utc_now(), -60, :second])

      result =
        try do
          assert_recent(old, 5)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "60" or result =~ "second"
    end