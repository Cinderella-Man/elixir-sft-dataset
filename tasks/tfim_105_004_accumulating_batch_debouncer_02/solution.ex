  test "accumulates all items in a burst and flushes them once, in order" do
    BatchDebouncer.call("k", 150, :a, report(:batch))
    BatchDebouncer.call("k", 150, :b, report(:batch))
    BatchDebouncer.call("k", 150, :c, report(:batch))

    assert_receive {:batch, [:a, :b, :c]}, 600
    # Only one flush for the burst.
    refute_receive {:batch, _}, 250
  end