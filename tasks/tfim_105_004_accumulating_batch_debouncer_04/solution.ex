  test "does not flush before the delay elapses" do
    BatchDebouncer.call("k", 200, :x, report(:batch))
    refute_receive {:batch, _}, 120
    assert_receive {:batch, [:x]}, 400
  end