  test "terminal states reject every event" do
    completed = %{Workflow.new(%{}) | state: :completed}

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(completed, event, %{approver: "x", reason: "y"})
    end
  end