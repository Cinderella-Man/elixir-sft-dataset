  test "approve guard checks approved_by string" do
    rec = submittable_draft()
    {:ok, submitted} = Workflow.transition(rec, :submit)

    assert {:ok, %{state: :approved}} = Workflow.transition(submitted, :approve)

    bad = %{submitted | approved_by: ""}
    assert {:error, :guard_failed, :submitted, :approve} = Workflow.transition(bad, :approve)
  end