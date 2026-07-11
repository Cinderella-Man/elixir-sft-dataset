  test "a reclaimed invalid connection is replaced for a waiting caller" do
    {_counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_crash_val, max_size: 1, create: create, validate: validate, destroy: destroy}
    )

    {holder, {:ok, c0}} = spawn_holder(:vp_crash_val, 1_000)
    assert c0 == {:conn, 0}

    parent = self()
    spawn(fn -> send(parent, {:result, ValidatingPool.checkout(:vp_crash_val, 1_000)}) end)
    Process.sleep(50)
    refute_received {:result, _}

    poison.(c0)
    Process.exit(holder, :kill)

    assert_receive {:result, {:ok, cnew}}, 1_000
    assert cnew != c0
    assert cnew == {:conn, 1}
    assert destroyed_list.() == [c0]
  end