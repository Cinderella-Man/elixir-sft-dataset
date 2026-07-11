  test "an invalid connection is discarded and replaced on checkout" do
    {_counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_val, max_size: 1, create: create, validate: validate, destroy: destroy}
    )

    assert {:ok, c0} = ValidatingPool.checkout(:vp_val, 100)
    assert c0 == {:conn, 0}
    assert :ok = ValidatingPool.checkin(:vp_val, c0)

    # Poison the returned connection: the next checkout must not hand it out.
    poison.(c0)
    assert {:ok, c1} = ValidatingPool.checkout(:vp_val, 100)
    assert c1 != c0
    assert c1 == {:conn, 1}
    assert destroyed_list.() == [c0]

    s = ValidatingPool.stats(:vp_val)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end