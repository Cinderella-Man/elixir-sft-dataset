  test "stage/4 rejects a non-atom name and a function of the wrong arity" do
    pipeline = Pipeline.new()

    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(pipeline, "not_an_atom", fn v -> {:ok, v} end)
    end

    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(pipeline, :bad_arity, fn a, b -> {:ok, a + b} end)
    end
  end