  test "each push resets the idle timer (debounce)" do
    agg = start_agg(idle_ms: 200, max_wait_ms: 5_000, batch_size: 1_000_000)

    DebounceAggregator.push(agg, :a)

    # Push :b before :a's idle window elapses; this resets the idle timer.
    Process.sleep(120)
    DebounceAggregator.push(agg, :b)

    # Idle is measured from :b now, so no flush should have happened yet
    # (a naive timer keyed to :a would have fired around here).
    refute_receive {:flushed, _}, 120

    # After quiet from :b, both events flush together — proving :a was NOT
    # flushed alone at its original idle deadline.
    assert_receive {:flushed, [:a, :b]}, 400
  end