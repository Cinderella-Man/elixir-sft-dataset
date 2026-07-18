  test "cancel with a non-binary reason succeeds without stamping cancelled_reason" do
    rec = Workflow.new(%{items: [:a], note: "keep"})
    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)

    {:ok, done} = Workflow.transition(rec, :cancel, %{reason: 123})
    assert done.state == :cancelled
    refute Map.has_key?(done, :cancelled_reason)
    assert done.note == "keep"
    assert done.items == [:a]

    {:ok, done2} = Workflow.transition(rec, :cancel, %{reason: nil})
    assert done2.state == :cancelled
    refute Map.has_key?(done2, :cancelled_reason)
  end