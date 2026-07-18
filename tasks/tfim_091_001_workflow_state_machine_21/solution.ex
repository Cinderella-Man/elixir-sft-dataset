  test "can? does not mutate or transition the record" do
    rec = submittable_draft()
    assert Workflow.can?(rec, :submit) == true
    # record is still in draft
    assert rec.state == :draft
  end