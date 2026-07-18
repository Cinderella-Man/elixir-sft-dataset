  test "timeout 0 fails at once at capacity and succeeds once a connection is free" do
    start_supervised!({Pool, name: :pool_zero, min_size: 0, max_size: 1})

    assert {:ok, c} = Pool.checkout(:pool_zero, 100)
    assert {:error, :timeout} = Pool.checkout(:pool_zero, 0)

    assert :ok = Pool.checkin(:pool_zero, c)
    assert {:ok, ^c} = Pool.checkout(:pool_zero, 0)
  end