  test "new/1 merges attrs and forces :draft" do
    rec = Workflow.new(%{items: [1, 2], approved_by: "x", state: :completed})
    assert rec.state == :draft
    assert rec.items == [1, 2]
    assert rec.approved_by == "x"
  end