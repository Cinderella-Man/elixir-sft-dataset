  test "undo preserves unrelated domain fields" do
    rec = Workflow.new(%{items: [:a], approved_by: "m", tag: 99})
    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.undo(rec)
    assert rec.tag == 99
    assert rec.items == [:a]
  end