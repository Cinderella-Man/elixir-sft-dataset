  test "unrelated fields survive a guardless transition into a terminal state" do
    rec = Workflow.new(%{items: [:a], approved_by: "boss", meta: %{customer: "acme"}, tag: 42})

    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.transition(rec, :approve)
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, done} = Workflow.transition(rec, :complete)

    assert done.state == :completed
    assert Map.delete(done, :state) == Map.delete(rec, :state)
    assert done.meta == %{customer: "acme"}
    assert done.tag == 42
    assert done.items == [:a]
    assert done.approved_by == "boss"
  end