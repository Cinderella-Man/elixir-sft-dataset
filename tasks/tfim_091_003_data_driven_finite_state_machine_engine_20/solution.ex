  test "states/1 includes the initial state when no transition mentions it" do
    m = Workflow.define(:start, [{:go, :a, :b}])
    states = Workflow.states(m)

    assert Enum.sort(Enum.uniq(states)) == [:a, :b, :start]
    assert length(states) == 3
  end