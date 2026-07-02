  test "checkout all -> next times out -> checkin one -> next succeeds" do
    start_supervised!({Pool, name: :pool_basic, max_size: 2})

    assert {:ok, c1} = Pool.checkout(:pool_basic, 100)
    assert {:ok, _c2} = Pool.checkout(:pool_basic, 100)

    # Pool exhausted: the next checkout must time out cleanly.
    assert {:error, :timeout} = Pool.checkout(:pool_basic, 50)

    # Return one connection...
    assert :ok = Pool.checkin(:pool_basic, c1)

    # ...and now a checkout succeeds again, reusing the returned connection.
    assert {:ok, c3} = Pool.checkout(:pool_basic, 100)
    assert c3 == c1
  end