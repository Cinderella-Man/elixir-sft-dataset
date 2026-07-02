  test "define raises on duplicate event/from pair" do
    assert_raise ArgumentError, fn ->
      Workflow.define(:a, [{:go, :a, :b}, {:go, :a, :c}])
    end
  end