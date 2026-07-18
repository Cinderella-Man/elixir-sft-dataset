  test "a guard returning nil is falsy and fails the transition" do
    m = Workflow.define(:a, [{:go, :a, :b, fn _r -> nil end}])
    rec = Workflow.new(m, %{tag: 1})

    assert {:error, :guard_failed, :a, :go} = Workflow.transition(m, rec, :go)
    assert Workflow.can?(m, rec, :go) == false
    assert rec == %{state: :a, tag: 1}
  end