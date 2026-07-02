  test "states/1 for the door machine" do
    states = Workflow.states(door_machine())
    assert Enum.sort(Enum.uniq(states)) == [:closed, :locked, :opened]
  end