    test "a difference exactly equal to the tolerance passes" do
      three_seconds_ago = apply(DateTime, :add, [DateTime.utc_now(), -3, :second])
      assert_recent(three_seconds_ago, 3)
    end