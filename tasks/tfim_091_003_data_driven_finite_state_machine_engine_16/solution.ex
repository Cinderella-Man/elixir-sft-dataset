  test "approve guard is enforced from the data-defined edge" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:a], approved_by: "boss"})
    {:ok, rec} = Workflow.transition(m, rec, :submit)

    assert {:ok, %{state: :approved}} = Workflow.transition(m, rec, :approve)

    bad = %{rec | approved_by: nil}

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(m, bad, :approve)
  end