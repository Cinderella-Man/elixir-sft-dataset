  test "different keys accumulate independent batches" do
    BatchDebouncer.call("a", 150, :a1, report(:batch))
    BatchDebouncer.call("a", 150, :a2, report(:batch))
    BatchDebouncer.call("b", 150, :b1, report(:batch))

    assert_receive {:batch, [:a1, :a2]}, 500
    assert_receive {:batch, [:b1]}, 500
  end