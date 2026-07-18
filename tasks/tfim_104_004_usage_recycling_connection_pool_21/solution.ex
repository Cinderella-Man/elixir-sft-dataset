  test "a crash while holding retires the connection and hands a waiter a fresh one" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool,
       name: :rp_crash_waiter, max_size: 1, max_uses: 1, create: create, destroy: destroy}
    )

    parent = self()

    await_blocked = fn pid ->
      Enum.reduce_while(1..2_000, :never, fn _, acc ->
        case Process.info(pid, :status) do
          {:status, :waiting} ->
            {:halt, :blocked}

          _ ->
            Process.sleep(1)
            {:cont, acc}
        end
      end)
    end

    {holder, {:ok, c0}} = spawn_holder(:rp_crash_waiter, 5_000)
    assert c0 == {:conn, 0}

    waiter =
      spawn(fn ->
        send(parent, {:served, RecyclingPool.checkout(:rp_crash_waiter, 5_000)})

        receive do
          :release -> :ok
        end
      end)

    assert await_blocked.(waiter) == :blocked

    Process.exit(holder, :kill)

    assert_receive {:served, {:ok, cnew}}, 5_000
    assert cnew == {:conn, 1}
    assert destroyed.() == [c0]

    s = RecyclingPool.stats(:rp_crash_waiter)
    assert s.total == 1
    assert s.in_use == 1
    assert s.available == 0

    send(waiter, :release)
  end