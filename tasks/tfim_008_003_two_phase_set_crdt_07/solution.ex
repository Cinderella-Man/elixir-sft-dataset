  test "re-adding a removed element raises ArgumentError", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    assert_raise ArgumentError, fn ->
      TwoPhaseSet.add(s, :x)
    end
  end