  test "can?/3 defaults payload to empty and does not mutate" do
    rec = draft()
    assert Workflow.can?(rec, :submit) == true
    assert rec.state == :draft
  end