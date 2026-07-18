  test "identical items are appended rather than deduplicated" do
    BatchDebouncer.call("k", 150, :dup, report(:batch))
    BatchDebouncer.call("k", 150, :dup, report(:batch))

    assert BatchDebouncer.pending("k") == 2
    assert_receive {:batch, [:dup, :dup]}, 600
  end