  test "keys lists a key whose entries have all aged past the query window",
       %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)

    Clock.advance(5_000)

    # The entry is far outside its 1_000ms query window (so usage reads 0) yet
    # still within max_window_ms (10_000), so keys/1 must still list the key.
    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
    assert QuotaTracker.keys(t) == [:api]
  end