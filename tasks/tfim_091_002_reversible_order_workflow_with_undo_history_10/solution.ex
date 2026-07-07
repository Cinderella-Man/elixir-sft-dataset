  test "undo works from a terminal state" do
    rec = full_path_completed()
    assert rec.state == :completed
    {:ok, back} = Workflow.undo(rec)
    assert back.state == :in_progress
  end