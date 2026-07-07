  test "undo on empty history returns nothing_to_undo" do
    rec = submittable_draft()
    assert Workflow.undo(rec) == {:error, :nothing_to_undo}
  end