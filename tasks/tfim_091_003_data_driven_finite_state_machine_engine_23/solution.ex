  test "define raises for a 2-arity guard and for a non-function guard" do
    assert_raise ArgumentError, fn ->
      Workflow.define(:a, [{:go, :a, :b, fn _x, _y -> true end}])
    end

    assert_raise ArgumentError, fn ->
      Workflow.define(:a, [{:go, :a, :b, :always}])
    end
  end