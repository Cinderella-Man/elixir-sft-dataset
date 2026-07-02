  test "new/1 merges attrs and forces :draft" do
    rec = Workflow.new(%{items: [1], state: :completed, tag: 3})
    assert rec.state == :draft
    assert rec.items == [1]
    assert rec.tag == 3
  end