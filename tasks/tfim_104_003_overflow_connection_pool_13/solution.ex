  test "a crashed holder's connection goes to a blocked waiter and stays alive" do
    parent = self()
    destroy = fn conn -> send(parent, {:destroyed, conn}) end

    start_supervised!(
      {OverflowPool, name: :op_crash_wait, size: 1, max_overflow: 1, destroy: destroy}
    )

    assert {:ok, _c1} = OverflowPool.checkout(:op_crash_wait, 100)
    {holder, {:ok, c2}} = spawn_holder(:op_crash_wait, 1_000)

    waiter =
      spawn(fn ->
        send(parent, {:served, OverflowPool.checkout(:op_crash_wait, 5_000)})

        receive do
          :release -> :ok
        end
      end)

    # The pool is at size + max_overflow, so this caller is enqueued as a waiter.
    refute_receive {:served, _}, 100

    Process.exit(holder, :kill)

    # Demand still exists, so reclamation hands the connection over instead of destroying it.
    assert_receive {:served, {:ok, got}}, 1_000
    assert got == c2
    refute_receive {:destroyed, _}, 100
    assert OverflowPool.stats(:op_crash_wait).total == 2

    send(waiter, :release)
  end