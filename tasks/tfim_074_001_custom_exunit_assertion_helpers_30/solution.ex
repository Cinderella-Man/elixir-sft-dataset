    test "nil, a Date, a string and an integer all fail the assertion" do
      # apply/3 keeps each value opaque to the type checker so the macro's
      # fallback branch stays reachable.
      for value <- [nil, Date.utc_today(), "2024-01-01T00:00:00Z", 1_704_067_200] do
        assert_raise ExUnit.AssertionError, fn ->
          assert_recent(apply(Function, :identity, [value]))
        end
      end
    end