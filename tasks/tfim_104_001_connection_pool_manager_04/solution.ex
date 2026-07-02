  test "checkin returns :ok and makes the connection available again" do
    start_supervised!({Pool, name: :pool_checkin, max_size: 1})

    assert {:ok, c} = Pool.checkout(:pool_checkin, 100)
    assert {:error, :timeout} = Pool.checkout(:pool_checkin, 20)
    assert :ok = Pool.checkin(:pool_checkin, c)
    assert {:ok, ^c} = Pool.checkout(:pool_checkin, 100)
  end