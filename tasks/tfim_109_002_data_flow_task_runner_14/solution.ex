  test "a non-one-arity func raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      DataFlowRunner.submit(:runner, :a, func: fn -> :zero end)
    end
  end