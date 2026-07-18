    test "a tolerance of 0 passes for the current second" do
      assert_recent(apply(DateTime, :utc_now, []), 0)
    end