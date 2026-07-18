  test "call/4 refuses a handler whose arity is not one" do
    assert_raise FunctionClauseError, fn ->
      BatchDebouncer.call("k", 50, :item, fn _a, _b -> :ok end)
    end
  end