  test "can?/3 reflects edges and guards" do
    m = order_machine()
    ok = Workflow.new(m, %{items: [:a]})
    bad = Workflow.new(m, %{items: []})

    assert Workflow.can?(m, ok, :submit) == true
    assert Workflow.can?(m, bad, :submit) == false
    assert Workflow.can?(m, ok, :approve) == false
  end