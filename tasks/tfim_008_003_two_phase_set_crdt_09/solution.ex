  test "removing an already-removed element raises ArgumentError", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    assert_raise ArgumentError, fn ->
      TwoPhaseSet.remove(s, :x)
    end
  end