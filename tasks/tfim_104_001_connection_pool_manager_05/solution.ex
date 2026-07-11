  test "connections are created lazily, never beyond max, and reused" do
    {counter, create} = counting_create()

    start_supervised!({Pool, name: :pool_lazy, min_size: 0, max_size: 3, create: create})

    # Nothing created eagerly when min_size is 0.
    assert created(counter) == 0

    assert {:ok, a} = Pool.checkout(:pool_lazy, 100)
    assert {:ok, _b} = Pool.checkout(:pool_lazy, 100)
    assert {:ok, _c} = Pool.checkout(:pool_lazy, 100)
    assert created(counter) == 3

    # At max: a further checkout times out and creates nothing new.
    assert {:error, :timeout} = Pool.checkout(:pool_lazy, 50)
    assert created(counter) == 3

    # Returned connections are reused, not recreated.
    assert :ok = Pool.checkin(:pool_lazy, a)
    assert {:ok, a2} = Pool.checkout(:pool_lazy, 100)
    assert a2 == a
    assert created(counter) == 3
  end