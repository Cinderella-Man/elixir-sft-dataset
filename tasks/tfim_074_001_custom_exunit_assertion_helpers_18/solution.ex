    test "failure message includes the actual datetime and the diff" do
      old = apply(DateTime, :add, [DateTime.utc_now(), -100, :second])

      message =
        try do
          assert_recent(old, 5)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      # Should tell us both what the value was and how far off it is
      assert message =~ "tolerance"
    end