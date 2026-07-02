  test "states/0 lists all seven states" do
    states = Workflow.states()
    for s <- [:draft, :submitted, :approved, :in_progress, :completed, :rejected, :cancelled] do
      assert s in states, "expected #{inspect(s)} in #{inspect(states)}"
    end
    assert length(Enum.uniq(states)) == 7
  end