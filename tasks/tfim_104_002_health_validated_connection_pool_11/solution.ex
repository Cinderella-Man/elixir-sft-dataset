  test "every invalid available connection is discarded before a fresh one is created" do
    {_counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_sweep, max_size: 3, create: create, validate: validate, destroy: destroy}
    )

    conns =
      for _ <- 1..3 do
        assert {:ok, c} = ValidatingPool.checkout(:vp_sweep, 100)
        c
      end

    Enum.each(conns, fn c -> assert :ok = ValidatingPool.checkin(:vp_sweep, c) end)
    Enum.each(conns, poison)

    # All three available connections are stale: each must be validated, destroyed
    # and dropped (total 3 -> 0) so that a fresh one can be created under max_size.
    assert {:ok, fresh} = ValidatingPool.checkout(:vp_sweep, 100)
    assert fresh == {:conn, 3}
    assert Enum.sort(destroyed_list.()) == Enum.sort(conns)

    s = ValidatingPool.stats(:vp_sweep)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end