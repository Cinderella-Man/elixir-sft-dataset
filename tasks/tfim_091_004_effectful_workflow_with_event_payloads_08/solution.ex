  test "cancel without a reason still succeeds and adds no reason field" do
    rec = submitted()
    {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :cancel)
    assert rec.state == :cancelled
    refute Map.has_key?(rec, :cancelled_reason)
  end