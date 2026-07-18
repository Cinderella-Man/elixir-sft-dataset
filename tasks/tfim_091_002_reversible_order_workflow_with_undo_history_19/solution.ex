  test "undo succeeds even when the original transition's guard would now fail" do
    rec = Workflow.new(%{items: [:widget], approved_by: "manager"})
    {:ok, submitted} = Workflow.transition(rec, :submit)
    {:ok, approved} = Workflow.transition(submitted, :approve)

    guard_hostile = %{approved | items: [], approved_by: ""}

    {:ok, back_to_submitted} = Workflow.undo(guard_hostile)
    assert back_to_submitted.state == :submitted
    assert Workflow.history(back_to_submitted) == [:submit]

    {:ok, back_to_draft} = Workflow.undo(back_to_submitted)
    assert back_to_draft.state == :draft
    assert Workflow.history(back_to_draft) == []
  end