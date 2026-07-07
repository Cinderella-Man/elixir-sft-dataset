  test "wrong-stage valid event still returns invalid_transition" do
    rec = approvable_submitted()
    # :start is only valid from :approved, not :submitted
    assert {:error, :invalid_transition, :submitted, :start} =
             Workflow.transition(rec, :start)

    # :submit only valid from :draft
    assert {:error, :invalid_transition, :submitted, :submit} =
             Workflow.transition(rec, :submit)
  end