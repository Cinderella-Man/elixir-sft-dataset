  test "invalid edge reports invalid_transition even when the guard would fail" do
    rec = draft()

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve, %{})

    assert {:error, :invalid_transition, :draft, :reject} =
             Workflow.transition(rec, :reject, %{reason: ""})

    {:ok, rejected} = Workflow.transition(submitted(), :reject, %{reason: "dup"})

    assert {:error, :invalid_transition, :rejected, :approve} =
             Workflow.transition(rejected, :approve, %{approver: nil})
  end