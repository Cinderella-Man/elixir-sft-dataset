  test "submit guard is record-based and ignores the payload" do
    empty = Workflow.new(%{items: []})

    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(empty, :submit, %{whatever: 1})

    ok = Workflow.new(%{items: [:a]})
    assert {:ok, %{state: :submitted}} = Workflow.transition(ok, :submit)
  end