  test "every connection held by a crashed process is reclaimed" do
    start_supervised!({Pool, name: :pool_crash_many, min_size: 0, max_size: 2})

    parent = self()

    holder =
      spawn(fn ->
        {:ok, c1} = Pool.checkout(:pool_crash_many, 1_000)
        {:ok, c2} = Pool.checkout(:pool_crash_many, 1_000)
        send(parent, {:held, self(), c1, c2})

        receive do
          :release -> :ok
        end
      end)

    assert_receive {:held, ^holder, c1, c2}, 1_000
    assert {:error, :timeout} = Pool.checkout(:pool_crash_many, 50)

    Process.exit(holder, :kill)

    assert {:ok, r1} = Pool.checkout(:pool_crash_many, 1_000)
    assert {:ok, r2} = Pool.checkout(:pool_crash_many, 1_000)
    assert Enum.sort([r1, r2]) == Enum.sort([c1, c2])
    assert %{available: 0, in_use: 2, total: 2} = Pool.stats(:pool_crash_many)
  end