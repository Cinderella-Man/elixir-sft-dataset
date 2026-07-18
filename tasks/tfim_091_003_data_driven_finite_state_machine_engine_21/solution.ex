  test "the same event from different from-states is not a duplicate" do
    m = Workflow.define(:a, [{:go, :a, :b}, {:go, :b, :c}])
    rec = Workflow.new(m)

    assert {:ok, rec} = Workflow.transition(m, rec, :go)
    assert rec.state == :b
    assert {:ok, %{state: :c}} = Workflow.transition(m, rec, :go)
  end