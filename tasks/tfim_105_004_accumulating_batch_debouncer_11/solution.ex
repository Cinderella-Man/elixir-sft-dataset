  test "re-arming with a shorter delay flushes once and the replaced deadline never fires" do
    BatchDebouncer.call("k", 400, :a, report(:batch))
    BatchDebouncer.call("k", 60, :b, report(:batch))

    assert_receive {:batch, [:a, :b]}, 300
    assert BatchDebouncer.pending("k") == 0

    # The replaced 400ms deadline must not produce a second flush.
    refute_receive {:batch, _}, 500
  end