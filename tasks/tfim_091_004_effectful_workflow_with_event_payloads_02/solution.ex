  test "new/0 starts in :draft" do
    assert %{state: :draft} = Workflow.new()
  end