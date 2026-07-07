  test "reject side branch: submitted -> rejected" do
    rec = approvable_submitted()
    assert {:ok, rec} = Workflow.transition(rec, :reject)
    assert rec.state == :rejected
  end