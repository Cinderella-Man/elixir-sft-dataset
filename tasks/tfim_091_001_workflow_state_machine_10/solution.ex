  test "unknown event is an invalid transition" do
    rec = submittable_draft()
    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(rec, :teleport)
  end