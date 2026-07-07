  test "reject stamps the rejection reason from the payload" do
    {:ok, rec} = Workflow.transition(submitted(), :reject, %{reason: "duplicate"})
    assert rec.state == :rejected
    assert rec.rejection_reason == "duplicate"
  end