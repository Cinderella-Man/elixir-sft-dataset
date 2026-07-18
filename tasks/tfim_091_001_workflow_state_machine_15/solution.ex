  test "submit guard fails on non-list items" do
    rec = Workflow.new(%{items: "not a list"})

    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
  end