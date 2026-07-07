  test "cancel side branch: in_progress -> cancelled" do
    rec = approvable_submitted()
    {:ok, rec} = Workflow.transition(rec, :approve)
    {:ok, rec} = Workflow.transition(rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(rec, :cancel)
    assert rec.state == :cancelled
  end