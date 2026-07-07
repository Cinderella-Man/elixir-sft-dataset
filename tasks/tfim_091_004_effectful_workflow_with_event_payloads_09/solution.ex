  test "transition preserves unrelated fields" do
    rec = Workflow.new(%{items: [:a], meta: %{c: "acme"}})
    {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.meta == %{c: "acme"}
    assert rec.items == [:a]
  end