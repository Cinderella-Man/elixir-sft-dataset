  test "default max_window_ms evicts entries after one hour" do
    {:ok, t2} =
      QuotaTracker.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    {:ok, _} = QuotaTracker.record(t2, :api, 5, 10, 1_000)

    # Just under the default hour: lazy cleanup on access must retain the entry.
    Clock.advance(3_599_999)
    {:ok, _} = QuotaTracker.usage(t2, :api, 100_000_000)
    assert QuotaTracker.keys(t2) == [:api]

    # At the default hour: lazy cleanup on access must evict, dropping the key.
    Clock.advance(1)
    {:ok, _} = QuotaTracker.usage(t2, :api, 100_000_000)
    assert QuotaTracker.keys(t2) == []
  end