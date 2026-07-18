  test "unguarded edges pass even when both guard fields are unusable" do
    draft = Workflow.new(%{items: [:x], approved_by: "someone"})
    {:ok, submitted} = Workflow.transition(draft, :submit)
    bare = %{submitted | items: [], approved_by: nil}

    # :reject has no guard.
    assert {:ok, %{state: :rejected}} = Workflow.transition(bare, :reject)
    assert Workflow.can?(bare, :reject) == true

    approved = %{bare | state: :approved}
    assert {:ok, in_progress} = Workflow.transition(approved, :start)
    assert in_progress.state == :in_progress
    assert Workflow.can?(approved, :start) == true

    assert {:ok, %{state: :completed}} = Workflow.transition(in_progress, :complete)
    assert {:ok, %{state: :cancelled}} = Workflow.transition(in_progress, :cancel)
  end