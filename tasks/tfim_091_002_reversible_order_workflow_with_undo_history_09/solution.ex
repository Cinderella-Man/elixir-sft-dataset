  test "undo can be applied repeatedly, unwinding the path" do
    rec = full_path_completed()

    {:ok, rec} = Workflow.undo(rec)
    assert rec.state == :in_progress
    assert Workflow.history(rec) == [:submit, :approve, :start]

    {:ok, rec} = Workflow.undo(rec)
    assert rec.state == :approved

    {:ok, rec} = Workflow.undo(rec)
    assert rec.state == :submitted

    {:ok, rec} = Workflow.undo(rec)
    assert rec.state == :draft
    assert Workflow.history(rec) == []
  end