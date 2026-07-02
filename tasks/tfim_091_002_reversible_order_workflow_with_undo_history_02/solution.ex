  test "new/0 starts in :draft with empty history" do
    rec = Workflow.new()
    assert rec.state == :draft
    assert rec.history == []
  end