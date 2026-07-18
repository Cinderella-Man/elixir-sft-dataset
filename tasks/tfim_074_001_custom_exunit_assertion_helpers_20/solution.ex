    test "default tolerance is exactly 5 seconds: 6s old fails" do
      six_seconds_ago = apply(DateTime, :add, [DateTime.utc_now(), -6, :second])

      result =
        try do
          assert_recent(six_seconds_ago)
          :no_failure
        rescue
          ExUnit.AssertionError -> :failed
        end

      assert result == :failed
    end