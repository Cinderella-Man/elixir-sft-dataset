  test "min_size connections are created eagerly at startup" do
    {counter, create} = counting_create()

    start_supervised!({Pool, name: :pool_min, min_size: 2, max_size: 4, create: create})

    assert created(counter) == 2

    stats = Pool.stats(:pool_min)
    assert stats.total == 2
    assert stats.available == 2
    assert stats.in_use == 0
  end