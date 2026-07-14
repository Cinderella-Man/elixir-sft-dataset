  test "blocked waiters are served in FIFO order, longest-waiting first" do
    start_supervised!({OverflowPool, name: :op_fifo, size: 2, max_overflow: 0})

    assert {:ok, c1} = OverflowPool.checkout(:op_fifo, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_fifo, 100)

    parent = self()

    spawn_waiter = fn tag ->
      spawn(fn ->
        send(parent, {:served, tag, OverflowPool.checkout(:op_fifo, 5_000)})

        receive do
          :release -> :ok
        end
      end)
    end

    # The pool is at size + max_overflow, so each waiter blocks rather than
    # being served; the first waiter is therefore enqueued before the second.
    first = spawn_waiter.(:first)
    refute_receive {:served, :first, _}, 100

    second = spawn_waiter.(:second)
    refute_receive {:served, :second, _}, 100

    # The returned connection goes directly to the longest-waiting caller.
    assert :ok = OverflowPool.checkin(:op_fifo, c1)
    assert_receive {:served, :first, {:ok, got1}}, 1_000
    assert got1 == c1

    # One connection serves exactly one caller: the later waiter still blocks.
    refute_receive {:served, :second, _}, 100

    assert :ok = OverflowPool.checkin(:op_fifo, c2)
    assert_receive {:served, :second, {:ok, got2}}, 1_000
    assert got2 == c2

    send(first, :release)
    send(second, :release)
  end