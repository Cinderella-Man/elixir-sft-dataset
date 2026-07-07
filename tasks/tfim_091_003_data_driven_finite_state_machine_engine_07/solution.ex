  test "new/2 starts in the machine's initial state and merges attrs" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [1], state: :completed, tag: 5})
    assert rec.state == :draft
    assert rec.items == [1]
    assert rec.tag == 5
  end