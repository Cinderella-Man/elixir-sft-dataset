  test "invalid event from draft returns invalid_transition" do
    rec = submittable_draft()
    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve)

    assert {:error, :invalid_transition, :draft, :complete} =
             Workflow.transition(rec, :complete)

    assert {:error, :invalid_transition, :draft, :cancel} =
             Workflow.transition(rec, :cancel)
  end