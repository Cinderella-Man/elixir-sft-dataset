  test "can?/3 accounts for the payload" do
    rec = submitted()
    assert Workflow.can?(rec, :approve, %{approver: "m"}) == true
    assert Workflow.can?(rec, :approve, %{}) == false
    assert Workflow.can?(rec, :reject, %{reason: "r"}) == true
    assert Workflow.can?(rec, :reject) == false
  end