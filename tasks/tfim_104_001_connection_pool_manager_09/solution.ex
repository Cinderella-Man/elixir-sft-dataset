  test "a crashed holder's connection is reclaimed via monitoring" do
    start_supervised!({Pool, name: :pool_crash, min_size: 0, max_size: 1})

    {holder, result} = spawn_holder(:pool_crash, 1_000)
    assert {:ok, _conn} = result

    # Only one connection, and the (still-alive) holder owns it.
    assert {:error, :timeout} = Pool.checkout(:pool_crash, 50)

    # Kill the holder without it checking the connection back in.
    Process.exit(holder, :kill)

    # The pool must reclaim the connection and hand it out again.
    assert {:ok, _reclaimed} = Pool.checkout(:pool_crash, 1_000)

    stats = Pool.stats(:pool_crash)
    assert stats.total == 1
    assert stats.in_use == 1
    assert stats.available == 0
  end