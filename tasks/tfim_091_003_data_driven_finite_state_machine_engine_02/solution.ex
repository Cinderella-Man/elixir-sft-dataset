  test "states/1 lists all distinct states of the order machine" do
    states = Workflow.states(order_machine())

    for s <- [:draft, :submitted, :approved, :in_progress, :completed, :rejected, :cancelled] do
      assert s in states
    end

    assert length(Enum.uniq(states)) == 7
  end