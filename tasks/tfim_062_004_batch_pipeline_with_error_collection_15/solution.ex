  test "stage/3 rejects a function whose arity is not one" do
    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(Pipeline.new(), :bad_arity, fn a, b -> {:ok, {a, b}} end)
    end
  end