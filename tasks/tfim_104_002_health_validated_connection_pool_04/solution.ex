  test "min_size connections are created eagerly" do
    {counter, create} = counting_create()
    start_supervised!({ValidatingPool, name: :vp_min, min_size: 2, max_size: 4, create: create})
    assert created(counter) == 2
    s = ValidatingPool.stats(:vp_min)
    assert s.total == 2 and s.available == 2 and s.in_use == 0
  end