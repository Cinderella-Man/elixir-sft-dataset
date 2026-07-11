  test "a blocked checkout is served when another process checks in" do
    start_supervised!({Pool, name: :pool_wait, max_size: 2})

    {:ok, c1} = Pool.checkout(:pool_wait, 100)
    {:ok, _c2} = Pool.checkout(:pool_wait, 100)

    parent = self()

    _waiter =
      spawn(fn ->
        send(parent, {:result, Pool.checkout(:pool_wait, 1_000)})
      end)

    # Let the waiter block on an exhausted pool.
    Process.sleep(50)
    refute_received {:result, _}

    # Checking a connection in should unblock the waiter.
    assert :ok = Pool.checkin(:pool_wait, c1)
    assert_receive {:result, {:ok, _conn}}, 500
  end