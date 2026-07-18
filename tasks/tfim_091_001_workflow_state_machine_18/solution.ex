  test "approve guard passes with a non-empty approver string" do
    rec = approvable_submitted()
    assert {:ok, %{state: :approved}} = Workflow.transition(rec, :approve)
  end