  test "min_size equal to max_size fills the pool eagerly and never grows further" do
    {counter, create} = counting_create()

    start_supervised!({Pool, name: :pool_eq, min_size: 2, max_size: 2, create: create})

    assert created(counter) == 2
    assert %{available: 2, in_use: 0, total: 2, max: 2, min: 2} = Pool.stats(:pool_eq)

    assert {:ok, a} = Pool.checkout(:pool_eq, 100)
    assert {:ok, b} = Pool.checkout(:pool_eq, 100)
    assert a != b

    assert {:error, :timeout} = Pool.checkout(:pool_eq, 50)
    assert created(counter) == 2
  end