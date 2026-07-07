  test "new/2 respects a different machine's initial" do
    rec = Workflow.new(door_machine())
    assert rec.state == :closed
  end