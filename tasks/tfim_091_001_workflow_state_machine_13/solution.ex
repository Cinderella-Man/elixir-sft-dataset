  test "submit guard fails on empty items" do
    rec = Workflow.new(%{items: []})

    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
  end