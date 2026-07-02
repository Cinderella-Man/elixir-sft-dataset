  test "new/1 merges attrs and forces draft + empty history" do
    rec = Workflow.new(%{items: [1], state: :completed, history: [:garbage], tag: 7})
    assert rec.state == :draft
    assert rec.history == []
    assert rec.items == [1]
    assert rec.tag == 7
  end