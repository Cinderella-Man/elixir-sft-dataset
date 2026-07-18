  test "guard failure leaves the record unchanged" do
    rec = Workflow.new(%{items: []})

    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)

    # calling again yields the same result — no mutation happened
    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
  end