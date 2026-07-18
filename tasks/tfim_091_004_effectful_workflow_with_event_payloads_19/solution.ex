  test "rejected and cancelled records built via the API reject every event" do
    {:ok, rejected} = Workflow.transition(submitted(), :reject, %{reason: "dup"})

    {:ok, rec} = Workflow.transition(submitted(), :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, cancelled} = Workflow.transition(rec, :cancel, %{reason: "stop"})

    events = [:submit, :approve, :reject, :start, :complete, :cancel]

    for event <- events do
      assert {:error, :invalid_transition, :rejected, ^event} =
               Workflow.transition(rejected, event, %{approver: "x", reason: "y"})

      assert {:error, :invalid_transition, :cancelled, ^event} =
               Workflow.transition(cancelled, event, %{approver: "x", reason: "y"})

      assert Workflow.can?(rejected, event, %{approver: "x", reason: "y"}) == false
      assert Workflow.can?(cancelled, event, %{approver: "x", reason: "y"}) == false
    end
  end