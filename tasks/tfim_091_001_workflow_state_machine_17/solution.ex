  test "approve guard fails when approved_by is nil/missing/blank" do
    base = approvable_submitted()

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(%{base | approved_by: nil}, :approve)

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(%{base | approved_by: ""}, :approve)

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(%{base | approved_by: 123}, :approve)

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(Map.delete(base, :approved_by), :approve)
  end