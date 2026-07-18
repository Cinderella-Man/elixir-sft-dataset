  test "time-based flush is due a full interval after start when the first event arrives late" do
    # Batch size high enough that only the time trigger can fire.
    agg = start_agg(batch_size: 5, interval_ms: 400)

    # No flush has happened yet, so the interval is measured from start:
    # the deadline is t ~= 400. Buffer an event at t ~= 250.
    Process.sleep(250)
    Aggregator.push(agg, :a)

    # Measured from start (as promised), [:a] flushes ~150ms from now.
    # Measured from the push instead, it would take a further ~400ms.
    assert_receive {:flushed, [:a]}, 280
  end