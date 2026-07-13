  test "defaults are max_size 10, min_size 0, max_uses :infinity and an empty pool" do
    start_supervised!({RecyclingPool, name: :rp_defaults})

    s = RecyclingPool.stats(:rp_defaults)
    assert s.max == 10
    assert s.min == 0
    assert s.max_uses == :infinity
    assert s.total == 0
    assert s.available == 0
    assert s.in_use == 0
  end