  test "defaults to a base of 5 eager connections with no overflow allowed" do
    {counter, create} = counting_create()
    start_supervised!({OverflowPool, name: :op_defaults, create: create})

    # :size defaults to 5, so five connections exist eagerly at startup.
    assert created(counter) == 5

    s = OverflowPool.stats(:op_defaults)
    assert s.size == 5 and s.max_overflow == 0
    assert s.total == 5 and s.available == 5 and s.in_use == 0 and s.overflow == 0

    results = for _ <- 1..5, do: OverflowPool.checkout(:op_defaults, 100)
    assert Enum.all?(results, &match?({:ok, _}, &1))

    # :max_overflow defaults to 0, so the pool never grows past the base of 5.
    assert {:error, :timeout} = OverflowPool.checkout(:op_defaults, 50)
    assert created(counter) == 5

    s = OverflowPool.stats(:op_defaults)
    assert s.total == 5 and s.in_use == 5 and s.available == 0 and s.overflow == 0
  end