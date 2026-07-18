  test "no matching edge means no guard is ever invoked" do
    parent = self()

    spy = fn _r ->
      send(parent, :guard_ran)
      true
    end

    m = Workflow.define(:draft, [{:approve, :submitted, :approved, spy}])
    rec = Workflow.new(m, %{items: [:a]})

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(m, rec, :approve)

    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(m, rec, :teleport)

    assert Workflow.can?(m, rec, :approve) == false
    refute_received :guard_ran
  end