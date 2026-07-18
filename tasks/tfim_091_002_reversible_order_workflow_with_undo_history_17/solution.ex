  test "guard failure leaves the record and history unchanged" do
    rec = Workflow.new(%{items: []})
    assert {:error, :guard_failed, :draft, :submit} = Workflow.transition(rec, :submit)
    assert rec.state == :draft
    assert rec.history == []
  end