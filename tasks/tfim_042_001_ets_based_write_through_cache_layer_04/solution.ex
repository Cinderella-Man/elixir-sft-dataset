  test "fallback return value is correctly stored and returned", %{cl: cl} do
    CallTracker.set_return(%{name: "Alice", age: 30})
    {:ok, first} = CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)
    {:ok, second} = CacheLayer.fetch(cl, :users, "u:2", &CallTracker.fallback/0)

    assert first == %{name: "Alice", age: 30}
    assert first == second
    assert CallTracker.call_count() == 1
  end