  test "walks the full order happy path" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:widget], approved_by: "mgr"})

    assert {:ok, rec} = Workflow.transition(m, rec, :submit)
    assert rec.state == :submitted

    assert {:ok, rec} = Workflow.transition(m, rec, :approve)
    assert rec.state == :approved

    assert {:ok, rec} = Workflow.transition(m, rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(m, rec, :complete)
    assert rec.state == :completed
  end