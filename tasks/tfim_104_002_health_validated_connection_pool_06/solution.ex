  test "a valid connection is reused (validate not a discard)" do
    {_counter, create} = counting_create()
    {validate, destroy, _poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_reuse, max_size: 1, create: create, validate: validate, destroy: destroy}
    )

    assert {:ok, c0} = ValidatingPool.checkout(:vp_reuse, 100)
    assert :ok = ValidatingPool.checkin(:vp_reuse, c0)
    assert {:ok, ^c0} = ValidatingPool.checkout(:vp_reuse, 100)
    assert destroyed_list.() == []
  end