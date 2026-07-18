  test "terminal states (no outgoing edges) reject every event" do
    m = order_machine()
    completed = %{Workflow.new(m) | state: :completed}

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(m, completed, event)
    end
  end