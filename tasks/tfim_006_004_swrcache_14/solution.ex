  test "put rejects non-positive windows", %{c: c} do
    assert_raise FunctionClauseError, fn ->
      SwrCache.put(c, :a, 1, 0, 100, fn -> :_ end)
    end

    assert_raise FunctionClauseError, fn ->
      SwrCache.put(c, :a, 1, 100, 0, fn -> :_ end)
    end
  end