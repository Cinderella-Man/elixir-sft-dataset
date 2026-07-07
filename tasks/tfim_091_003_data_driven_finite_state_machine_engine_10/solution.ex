  test "door machine transitions independently" do
    m = door_machine()
    rec = Workflow.new(m)

    assert {:ok, rec} = Workflow.transition(m, rec, :lock)
    assert rec.state == :locked
    assert {:ok, rec} = Workflow.transition(m, rec, :unlock)
    assert rec.state == :closed
    assert {:ok, rec} = Workflow.transition(m, rec, :open)
    assert rec.state == :opened
  end