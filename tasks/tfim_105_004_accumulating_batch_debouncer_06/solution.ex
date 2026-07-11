  test "pending reflects the buffer size and resets after flush" do
    assert BatchDebouncer.pending("k") == 0

    BatchDebouncer.call("k", 300, :a, report(:batch))
    BatchDebouncer.call("k", 300, :b, report(:batch))
    assert BatchDebouncer.pending("k") == 2

    assert_receive {:batch, [:a, :b]}, 600
    assert BatchDebouncer.pending("k") == 0
  end