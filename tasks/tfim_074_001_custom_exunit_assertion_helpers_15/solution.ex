    test "passes for a datetime exactly at the tolerance boundary" do
      four_seconds_ago = apply(DateTime, :add, [DateTime.utc_now(), -4, :second])
      assert_recent(four_seconds_ago, 5)
    end