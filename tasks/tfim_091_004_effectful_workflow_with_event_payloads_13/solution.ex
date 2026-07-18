  test "guard failure leaves the record unchanged" do
    rec = submitted()

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(rec, :approve, %{})

    assert rec.state == :submitted
    refute Map.has_key?(rec, :approved_by)
  end