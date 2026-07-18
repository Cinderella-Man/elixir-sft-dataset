  test "adding an element tombstoned via merge but never locally added raises", %{s: s} do
    remote = %{added: MapSet.new(), removed: MapSet.new([:ghost])}
    TwoPhaseSet.merge(s, remote)

    assert_raise ArgumentError, fn ->
      TwoPhaseSet.add(s, :ghost)
    end
  end