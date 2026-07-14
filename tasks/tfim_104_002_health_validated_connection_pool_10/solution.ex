  test "a connection checked in stale is validated before reaching the waiter" do
    {_counter, create} = counting_create()
    {validate, destroy, poison, destroyed_list} = validation_tools()

    start_supervised!(
      {ValidatingPool,
       name: :vp_ci_val, max_size: 1, create: create, validate: validate, destroy: destroy}
    )

    assert {:ok, c0} = ValidatingPool.checkout(:vp_ci_val, 100)
    assert c0 == {:conn, 0}

    parent = self()

    spawn(fn ->
      send(parent, {:result, ValidatingPool.checkout(:vp_ci_val, 1_000)})
      # Stay alive past the assertions: a dead waiter would trigger the
      # pool's crash reclamation and change the stats being asserted.
      receive do
        :release -> :ok
      end
    end)

    refute_receive {:result, _}, 100

    # The held connection goes stale before it is returned: checking it in must
    # not hand it to the blocked caller; a fresh connection is created instead.
    poison.(c0)
    assert :ok = ValidatingPool.checkin(:vp_ci_val, c0)

    assert_receive {:result, {:ok, cnew}}, 1_000
    assert cnew != c0
    assert cnew == {:conn, 1}
    assert destroyed_list.() == [c0]

    s = ValidatingPool.stats(:vp_ci_val)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end