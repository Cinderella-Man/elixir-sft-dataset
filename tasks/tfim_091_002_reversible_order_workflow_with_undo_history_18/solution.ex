  test "can?/2 reflects valid edges and guards without mutating" do
    ok = submittable_draft()
    bad = Workflow.new(%{items: []})

    assert Workflow.can?(ok, :submit) == true
    assert Workflow.can?(bad, :submit) == false
    assert Workflow.can?(ok, :approve) == false

    # not mutated
    assert ok.state == :draft
    assert ok.history == []
  end