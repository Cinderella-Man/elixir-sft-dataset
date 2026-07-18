  test "max_size defaults to 10 and min_size defaults to 0" do
    start_supervised!({Pool, name: :pool_defaults})

    assert %{available: 0, in_use: 0, total: 0, max: 10, min: 0} = Pool.stats(:pool_defaults)

    conns = for _ <- 1..10, do: Pool.checkout(:pool_defaults, 100)
    assert Enum.all?(conns, &match?({:ok, _conn}, &1))
    assert conns |> Enum.uniq() |> length() == 10

    assert {:error, :timeout} = Pool.checkout(:pool_defaults, 50)
    assert %{total: 10, in_use: 10, max: 10, min: 0} = Pool.stats(:pool_defaults)
  end