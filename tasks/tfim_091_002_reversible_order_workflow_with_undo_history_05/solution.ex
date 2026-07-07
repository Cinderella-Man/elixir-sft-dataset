  test "walks the full happy path and records history" do
    rec = full_path_completed()
    assert rec.state == :completed
    assert Workflow.history(rec) == [:submit, :approve, :start, :complete]
  end