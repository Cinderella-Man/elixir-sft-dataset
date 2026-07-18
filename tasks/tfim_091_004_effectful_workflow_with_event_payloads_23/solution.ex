  test "can?/3 is false for wrong-stage and unknown events" do
    rec = draft()

    assert Workflow.can?(rec, :approve, %{approver: "m"}) == false
    assert Workflow.can?(rec, :complete) == false
    assert Workflow.can?(rec, :teleport, %{approver: "m"}) == false
    assert Workflow.can?(Workflow.new(%{items: []}), :submit) == false
    assert Workflow.can?(rec, :submit, %{ignored: 1}) == true
  end