  test "invalid event from draft returns invalid_transition" do
    rec = submittable_draft()

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve)

    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(rec, :teleport)
  end