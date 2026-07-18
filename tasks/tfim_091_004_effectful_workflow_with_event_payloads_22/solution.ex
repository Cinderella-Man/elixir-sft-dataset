  test "approve, reject and complete effects preserve untouched fields" do
    base = Workflow.new(%{items: [:a], note: "hi", meta: %{c: "acme"}})
    {:ok, sub} = Workflow.transition(base, :submit)

    {:ok, rej} = Workflow.transition(sub, :reject, %{reason: "dup"})
    assert rej.rejection_reason == "dup"
    assert rej.note == "hi"
    assert rej.meta == %{c: "acme"}
    assert rej.items == [:a]

    {:ok, rec} = Workflow.transition(sub, :approve, %{approver: "manager"})
    assert rec.approved_by == "manager"
    assert rec.note == "hi"
    assert rec.meta == %{c: "acme"}

    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :complete, %{approver: "ignored"})
    assert rec.completed == true
    assert rec.approved_by == "manager"
    assert rec.note == "hi"
    assert rec.items == [:a]
  end