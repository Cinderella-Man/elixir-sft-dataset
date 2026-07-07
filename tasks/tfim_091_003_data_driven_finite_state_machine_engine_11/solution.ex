  test "transition preserves unrelated fields" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:a], meta: %{c: 1}})
    {:ok, rec} = Workflow.transition(m, rec, :submit)
    assert rec.meta == %{c: 1}
    assert rec.items == [:a]
  end