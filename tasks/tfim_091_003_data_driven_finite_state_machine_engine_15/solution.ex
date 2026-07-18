  test "guard failure returns guard_failed and leaves record unchanged" do
    m = order_machine()
    rec = Workflow.new(m, %{items: []})

    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(m, rec, :submit)

    assert rec.state == :draft
  end