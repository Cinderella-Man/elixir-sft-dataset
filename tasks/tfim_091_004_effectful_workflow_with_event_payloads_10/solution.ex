  test "approve guard requires a non-empty approver in the payload" do
    rec = submitted()

    for bad <- [%{}, %{approver: nil}, %{approver: ""}, %{approver: 123}] do
      assert {:error, :guard_failed, :submitted, :approve} =
               Workflow.transition(rec, :approve, bad)
    end

    assert {:ok, %{state: :approved}} =
             Workflow.transition(rec, :approve, %{approver: "ok"})
  end