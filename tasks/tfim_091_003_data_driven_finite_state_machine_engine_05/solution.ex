  test "define raises on malformed transition spec" do
    assert_raise ArgumentError, fn ->
      Workflow.define(:a, [{:go, :a}])
    end
  end