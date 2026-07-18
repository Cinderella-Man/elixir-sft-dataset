  test "max_size defaults to ten and min_size defaults to zero" do
    {counter, create} = counting_create()
    start_supervised!({ValidatingPool, name: :vp_defaults, create: create})

    s = ValidatingPool.stats(:vp_defaults)
    assert s.max == 10 and s.min == 0
    assert s.total == 0 and s.available == 0 and s.in_use == 0
    assert created(counter) == 0

    for _ <- 1..10, do: assert({:ok, _} = ValidatingPool.checkout(:vp_defaults, 100))
    assert {:error, :timeout} = ValidatingPool.checkout(:vp_defaults, 0)
    assert ValidatingPool.stats(:vp_defaults).total == 10
  end