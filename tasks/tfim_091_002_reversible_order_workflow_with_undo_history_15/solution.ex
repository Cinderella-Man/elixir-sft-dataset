  test "submit guard fails on empty/missing/non-list items" do
    for items <- [[], "no", nil] do
      rec = Workflow.new(%{items: items})
      assert {:error, :guard_failed, :draft, :submit} = Workflow.transition(rec, :submit)
    end

    missing = Workflow.new(%{})
    assert {:error, :guard_failed, :draft, :submit} = Workflow.transition(missing, :submit)
  end