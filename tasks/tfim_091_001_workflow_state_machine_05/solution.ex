  test "walks the full happy path draft -> completed" do
    rec = submittable_draft()

    assert {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.state == :submitted

    rec = %{rec | approved_by: "manager"}
    assert {:ok, rec} = Workflow.transition(rec, :approve)
    assert rec.state == :approved

    assert {:ok, rec} = Workflow.transition(rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(rec, :complete)
    assert rec.state == :completed
  end