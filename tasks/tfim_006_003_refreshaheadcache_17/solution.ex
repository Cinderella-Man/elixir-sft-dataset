  test "after a failed refresh a later get retries the refresh", %{c: c} do
    {:ok, cnt} = Agent.start_link(fn -> 0 end)

    loader = fn ->
      n = Agent.get_and_update(cnt, fn n -> {n, n + 1} end)
      if n == 0, do: raise("boom"), else: :recovered
    end

    :ok = RefreshAheadCache.put(c, :a, :orig, 1_000, loader)

    Clock.advance(850)

    # First threshold crossing: schedules a refresh whose loader raises.
    assert {:ok, :orig} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)

    # The failure left the old value in place; this get crosses the threshold
    # again and must start a brand-new (this time succeeding) refresh.
    assert {:ok, :orig} = RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)

    assert {:ok, :recovered} = RefreshAheadCache.get(c, :a)
  end