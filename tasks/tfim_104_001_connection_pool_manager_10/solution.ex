  test "reclaimed connection is handed to a process already waiting" do
    start_supervised!({Pool, name: :pool_crash_wait, min_size: 0, max_size: 1})

    {holder, {:ok, _}} = spawn_holder(:pool_crash_wait, 1_000)

    parent = self()

    _waiter =
      spawn(fn ->
        send(parent, {:result, Pool.checkout(:pool_crash_wait, 1_000)})
      end)

    # Ensure the waiter is blocked before the holder dies.
    Process.sleep(50)
    refute_received {:result, _}

    Process.exit(holder, :kill)

    assert_receive {:result, {:ok, _conn}}, 1_000
  end