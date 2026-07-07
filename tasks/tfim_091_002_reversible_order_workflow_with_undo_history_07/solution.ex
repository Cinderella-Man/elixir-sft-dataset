  test "transition preserves unrelated fields" do
    rec = Workflow.new(%{items: [:a], meta: %{customer: "acme"}})
    {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.meta == %{customer: "acme"}
    assert rec.items == [:a]
  end