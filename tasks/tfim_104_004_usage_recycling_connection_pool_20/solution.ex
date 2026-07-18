  test "the fresh replacement for a retired connection goes to the longest-waiting caller" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool,
       name: :rp_fifo_fresh, max_size: 1, max_uses: 1, create: create, destroy: destroy}
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

    start_waiter = fn tag ->
      spawn(fn ->
        send(parent, {:served, tag, RecyclingPool.checkout(:rp_fifo_fresh, 5_000)})

        receive do
          :release -> :ok
        end
      end)
    end

    assert {:ok, c0} = RecyclingPool.checkout(:rp_fifo_fresh, 2_000)
    assert c0 == {:conn, 0}

    first = start_waiter.(:first)
    assert await_blocked.(first) == :blocked
    second = start_waiter.(:second)
    assert await_blocked.(second) == :blocked

    assert :ok = RecyclingPool.checkin(:rp_fifo_fresh, c0)
    assert_receive {:served, :first, {:ok, {:conn, 1}}}, 5_000
    refute_receive {:served, :second, _}, 200
    assert destroyed.() == [c0]

    send(first, :release)
    send(second, :release)
  end