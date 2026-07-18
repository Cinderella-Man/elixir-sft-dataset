  test "a timed-out waiter is retired and never receives a later connection" do
    start_supervised!({Pool, name: :pool_stale, min_size: 0, max_size: 1})

    {holder, {:ok, _conn}} = spawn_holder(:pool_stale, 1_000)
    parent = self()

    spawn(fn ->
      send(parent, {:waiter_result, Pool.checkout(:pool_stale, 50)})

      receive do
        late -> send(parent, {:late, late})
      after
        1_000 -> :ok
      end
    end)

    assert_receive {:waiter_result, {:error, :timeout}}, 1_000

    # The holder exits, freeing the only connection: the retired waiter must not act.
    send(holder, :release)
    refute_receive {:late, _}, 300

    assert %{available: 1, in_use: 0, total: 1} = Pool.stats(:pool_stale)
    assert {:ok, _reused} = Pool.checkout(:pool_stale, 100)
  end