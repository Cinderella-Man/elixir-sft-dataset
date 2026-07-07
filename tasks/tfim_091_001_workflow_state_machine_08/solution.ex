  test "transition preserves unrelated fields" do
    rec = Workflow.new(%{items: [:a], meta: %{customer: "acme"}, tag: 42})
    {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.meta == %{customer: "acme"}
    assert rec.tag == 42
    assert rec.items == [:a]
  end