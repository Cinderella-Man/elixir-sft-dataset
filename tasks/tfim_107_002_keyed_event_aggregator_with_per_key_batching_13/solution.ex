  test "a key's deadline stays anchored to the first push of the current batch" do
    agg = start_agg(batch_size: 10, interval_ms: 600)

    # t ~= 0: :a goes empty -> non-empty, arming its only timer (deadline t ~= 600).
    KeyedAggregator.push(agg, :a, 1)

    # t ~= 300: a second push into the already non-empty buffer must not move it.
    Process.sleep(300)
    KeyedAggregator.push(agg, :a, 2)

    # Nothing before the original deadline (t ~= 400 here).
    refute_receive {:flushed, :a, _}, 100

    # The anchored deadline fires at t ~= 600. A re-armed/extended timer would
    # instead fire at t ~= 900 and miss this window.
    assert_receive {:flushed, :a, [1, 2]}, 400
  end