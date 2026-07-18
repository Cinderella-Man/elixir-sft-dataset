  test "a waiter served before its deadline gets no timeout reply after that deadline" do
    start_supervised!({RecyclingPool, name: :rp_stale_timer, max_size: 1, max_uses: 10})
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

    assert {:ok, c} = RecyclingPool.checkout(:rp_stale_timer, 2_000)

    # The deadline is wide enough that the serve below always beats it, even on
    # a loaded machine. After being served, the waiter listens well past the
    # deadline, so a stale timeout reply (a timer the pool failed to cancel or
    # ignore) would surface as a stray message.
    waiter =
      spawn(fn ->
        send(parent, {:served, RecyclingPool.checkout(:rp_stale_timer, 1_500)})

        receive do
          other -> send(parent, {:stray, other})
        after
          2_000 -> send(parent, :quiet)
        end

        receive do
          :release -> :ok
        end
      end)

    assert await_blocked.(waiter) == :blocked
    assert :ok = RecyclingPool.checkin(:rp_stale_timer, c)
    assert_receive {:served, {:ok, ^c}}, 5_000

    # Two seconds of silence span the 1.5 s deadline: no stale timeout arrived.
    assert_receive :quiet, 10_000
    refute_received {:stray, _}

    s = RecyclingPool.stats(:rp_stale_timer)
    assert s.total == 1
    assert s.in_use == 1
    assert s.available == 0

    send(waiter, :release)
  end