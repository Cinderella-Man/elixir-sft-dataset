    test "default tolerance is exactly 5 seconds: 5s old passes" do
      five_seconds_ago = apply(DateTime, :add, [DateTime.utc_now(), -5, :second])
      assert_recent(five_seconds_ago)
    end