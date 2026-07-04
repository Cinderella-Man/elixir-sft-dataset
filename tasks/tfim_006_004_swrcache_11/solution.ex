  test "delete during in-flight revalidation discards the result", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok =
      SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(1_000)
    # triggers slow revalidation
    SwrCache.get(c, :a)

    SwrCache.delete(c, :a)

    :ok = wait_for_idle(c)
    assert :miss = SwrCache.get(c, :a)
    assert %{entries: 0} = SwrCache.stats(c)
  end