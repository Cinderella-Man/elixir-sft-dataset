  test "can?/2 reflects valid edges and guards" do
    draft_ok = submittable_draft()
    draft_bad = Workflow.new(%{items: []})

    assert Workflow.can?(draft_ok, :submit) == true
    assert Workflow.can?(draft_bad, :submit) == false
    assert Workflow.can?(draft_ok, :approve) == false

    submitted = approvable_submitted()
    assert Workflow.can?(submitted, :approve) == true
    assert Workflow.can?(submitted, :reject) == true
    assert Workflow.can?(%{submitted | approved_by: nil}, :approve) == false

    completed = %{Workflow.new(%{}) | state: :completed}
    assert Workflow.can?(completed, :complete) == false
  end