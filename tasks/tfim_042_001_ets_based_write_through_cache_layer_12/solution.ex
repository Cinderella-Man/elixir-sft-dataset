  test "tables are created on demand and can hold any term as value", %{cl: cl} do
    CallTracker.set_return([1, 2, 3])
    assert {:ok, [1, 2, 3]} = CacheLayer.fetch(cl, :lists, "my_list", &CallTracker.fallback/0)

    CallTracker.set_return(nil)
    # nil is a valid cached value — should NOT trigger a second fallback call
    assert {:ok, nil} = CacheLayer.fetch(cl, :nullables, "k", &CallTracker.fallback/0)
    assert {:ok, nil} = CacheLayer.fetch(cl, :nullables, "k", &CallTracker.fallback/0)
    assert CallTracker.call_count() == 2
  end