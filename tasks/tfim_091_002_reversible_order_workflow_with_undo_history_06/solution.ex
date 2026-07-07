  test "history/1 is chronological and side branches are recorded" do
    rec = submittable_draft()
    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.transition(rec, :reject)
    assert rec.state == :rejected
    assert Workflow.history(rec) == [:submit, :reject]
  end