  test "submit guard fails on missing items" do
    rec = Workflow.new(%{})

    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
  end