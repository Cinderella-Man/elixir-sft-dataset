  test "sweep keeps a stale entry whose revalidation failed", %{c: c} do
    Clock.set(0)
    parent = self()

    loader = fn ->
      send(parent, :loader_ran)
      raise "boom"
    end

    # fresh until 100, hard expiry at 2100.
    :ok = SwrCache.put(c, :a, :v1, 100, 2_000, loader)

    Clock.advance(150)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
    assert_receive :loader_ran, 500
    :ok = wait_for_idle(c)

    # Still inside the stale window (t=150 < 2100): sweep must NOT drop it.
    send(c, :sweep)
    assert %{entries: 1} = SwrCache.stats(c)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
  end