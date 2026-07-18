  test "door machine: opened cannot be locked" do
    m = door_machine()
    opened = %{Workflow.new(m) | state: :opened}

    assert {:error, :invalid_transition, :opened, :lock} =
             Workflow.transition(m, opened, :lock)
  end