  test "submit guard passes on non-empty items" do
    rec = Workflow.new(%{items: [:only_one]})
    assert {:ok, %{state: :submitted}} = Workflow.transition(rec, :submit)
  end