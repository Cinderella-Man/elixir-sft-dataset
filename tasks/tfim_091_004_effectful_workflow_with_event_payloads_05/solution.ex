  test "full happy path applies payload effects" do
    rec = draft()

    assert {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.state == :submitted

    assert {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "manager"})
    assert rec.state == :approved
    assert rec.approved_by == "manager"

    assert {:ok, rec} = Workflow.transition(rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(rec, :complete)
    assert rec.state == :completed
    assert rec.completed == true
  end