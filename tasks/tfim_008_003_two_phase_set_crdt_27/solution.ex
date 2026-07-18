  test "remove half the elements, verify membership", %{s: s} do
    elements = Enum.map(1..10, &:"e_#{&1}")
    Enum.each(elements, &TwoPhaseSet.add(s, &1))

    to_remove = Enum.take(elements, 5)
    Enum.each(to_remove, &TwoPhaseSet.remove(s, &1))

    remaining = Enum.drop(elements, 5) |> MapSet.new()
    assert TwoPhaseSet.members(s) == remaining
  end