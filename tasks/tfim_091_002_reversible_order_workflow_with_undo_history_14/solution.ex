  test "terminal states reject every forward event" do
    rec = full_path_completed()

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(rec, event)
    end
  end