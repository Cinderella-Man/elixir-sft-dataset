  test "a table's ETS table appears only on first use and is readable from other processes",
       %{cl: cl} do
    before_tabs = MapSet.new(:ets.all())

    # Touching a table that was never fetched must not create anything.
    assert :ok = CacheLayer.invalidate_all(cl, :lazy)
    assert :ok = CacheLayer.invalidate(cl, :lazy, "k")
    assert MapSet.difference(MapSet.new(:ets.all()), before_tabs) |> MapSet.size() == 0

    assert {:ok, :v} = CacheLayer.fetch(cl, :lazy, "k", fn -> :v end)

    created = MapSet.difference(MapSet.new(:ets.all()), before_tabs)
    assert MapSet.size(created) == 1

    # A :public table can be read straight from an unrelated process; a
    # :protected one would blow up in :ets.lookup outside the owner.
    boom = fn -> raise "fallback must not run on a cache hit" end
    task = Task.async(fn -> CacheLayer.fetch(cl, :lazy, "k", boom) end)
    assert {:ok, :v} = Task.await(task, 1_000)
  end