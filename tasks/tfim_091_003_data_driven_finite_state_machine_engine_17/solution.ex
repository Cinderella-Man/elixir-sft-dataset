  test "guardless edges always pass" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:a]})
    {:ok, rec} = Workflow.transition(m, rec, :submit)
    assert {:ok, %{state: :rejected}} = Workflow.transition(m, rec, :reject)
  end