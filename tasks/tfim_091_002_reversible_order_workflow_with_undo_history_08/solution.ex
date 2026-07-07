  test "undo reverts a single transition and trims history" do
    rec = submittable_draft()
    {:ok, submitted} = Workflow.transition(rec, :submit)
    assert submitted.state == :submitted

    {:ok, back} = Workflow.undo(submitted)
    assert back.state == :draft
    assert Workflow.history(back) == []
  end