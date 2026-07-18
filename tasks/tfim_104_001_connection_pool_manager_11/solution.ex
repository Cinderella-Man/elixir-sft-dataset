  test "checkin hands the connection to the longest-waiting caller first" do
    start_supervised!({Pool, name: :pool_fifo, min_size: 0, max_size: 1})

    assert {:ok, c1} = Pool.checkout(:pool_fifo, 100)

    # Both waiters stay alive after reporting, so the connection handed to the
    # first one is *not* reclaimed (and thus never reaches the second waiter).
    _first = spawn_waiter(:pool_fifo, :first_waiter, 2_000)
    # Bounded wait: the first waiter must be blocked (and enqueued) before the second.
    refute_receive {:first_waiter, _}, 200

    _second = spawn_waiter(:pool_fifo, :second_waiter, 2_000)
    refute_receive {:second_waiter, _}, 200

    assert :ok = Pool.checkin(:pool_fifo, c1)

    assert_receive {:first_waiter, {:ok, ^c1}}, 1_000
    refute_receive {:second_waiter, _}, 200
  end