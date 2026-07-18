  test "terminal states reject every event" do
    # completed
    completed = %{Workflow.new(%{}) | state: :completed}

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(completed, event)
    end

    # rejected
    rejected = %{Workflow.new(%{}) | state: :rejected}

    assert {:error, :invalid_transition, :rejected, :approve} =
             Workflow.transition(rejected, :approve)

    # cancelled
    cancelled = %{Workflow.new(%{}) | state: :cancelled}

    assert {:error, :invalid_transition, :cancelled, :start} =
             Workflow.transition(cancelled, :start)
  end