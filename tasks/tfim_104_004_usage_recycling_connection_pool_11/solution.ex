  test "min_size equal to max_size is accepted and pre-fills the pool" do
    start_supervised!({RecyclingPool, name: :rp_min_eq_max, min_size: 2, max_size: 2})

    s = RecyclingPool.stats(:rp_min_eq_max)
    assert s.min == 2
    assert s.max == 2
    assert s.total == 2
    assert s.available == 2
    assert s.in_use == 0
  end