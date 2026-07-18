  test "set_history_size/3 rejects a negative size via its guard", %{bus: bus} do
    assert_raise FunctionClauseError, fn ->
      ReplayEventBus.set_history_size(bus, "t", -1)
    end
  end