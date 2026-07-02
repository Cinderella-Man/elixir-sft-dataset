  test "creates :size connections eagerly at startup" do
    {counter, create} = counting_create()
    start_supervised!({OverflowPool, name: :op_eager, size: 3, max_overflow: 2, create: create})
    assert created(counter) == 3
    s = OverflowPool.stats(:op_eager)
    assert s.total == 3 and s.available == 3 and s.in_use == 0 and s.overflow == 0
  end