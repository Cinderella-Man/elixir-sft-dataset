  test "cancel with a reason stamps cancelled_reason" do
    rec = submitted()
    {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :cancel, %{reason: "customer changed mind"})
    assert rec.state == :cancelled
    assert rec.cancelled_reason == "customer changed mind"
  end