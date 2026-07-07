  test "reject guard requires a non-empty reason in the payload" do
    rec = submitted()

    assert {:error, :guard_failed, :submitted, :reject} =
             Workflow.transition(rec, :reject, %{})

    assert {:error, :guard_failed, :submitted, :reject} =
             Workflow.transition(rec, :reject, %{reason: ""})

    assert {:ok, %{state: :rejected}} =
             Workflow.transition(rec, :reject, %{reason: "bad"})
  end