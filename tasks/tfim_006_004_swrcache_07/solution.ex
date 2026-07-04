  test "fresh reads do NOT trigger revalidation", %{c: c} do
    start_supervised!({Loader, [:never_called]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    # Read 5 times well within the fresh window
    for _ <- 1..5, do: assert({:ok, :v1, :fresh} = SwrCache.get(c, :a))

    :ok = wait_for_idle(c)
    assert Loader.calls() == 0
  end