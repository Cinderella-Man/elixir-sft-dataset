  test "wrong-stage and unknown events are invalid" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:a]})

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(m, rec, :approve)

    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(m, rec, :teleport)
  end