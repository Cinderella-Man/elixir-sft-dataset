  test "a returned connection goes to the longest-waiting caller first" do
    start_supervised!({RecyclingPool, name: :rp_fifo_return, max_size: 1, max_uses: 10})
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
        send(parent, {:served, tag, RecyclingPool.checkout(:rp_fifo_return, 5_000)})

        receive do
          :release -> :ok
        end
      end)
    end

    assert {:ok, c} = RecyclingPool.checkout(:rp_fifo_return, 2_000)

    first = start_waiter.(:first)
    assert await_blocked.(first) == :blocked
    second = start_waiter.(:second)
    assert await_blocked.(second) == :blocked

    assert :ok = RecyclingPool.checkin(:rp_fifo_return, c)
    assert_receive {:served, :first, {:ok, ^c}}, 5_000
    refute_receive {:served, :second, _}, 200

    send(first, :release)
    send(second, :release)
  end