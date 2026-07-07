  test "define raises when guard is not a 1-arity function" do
    assert_raise ArgumentError, fn ->
      Workflow.define(:a, [{:go, :a, :b, fn -> true end}])
    end
  end