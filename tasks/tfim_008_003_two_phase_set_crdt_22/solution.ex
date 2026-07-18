  test "merge propagates tombstones — locally-added element disappears after merge", %{} do
    {:ok, n1} = TwoPhaseSet.start_link([])
    {:ok, n2} = TwoPhaseSet.start_link([])

    # Both add :x
    TwoPhaseSet.add(n1, :x)
    TwoPhaseSet.add(n2, :x)

    # n2 removes :x
    TwoPhaseSet.remove(n2, :x)

    # n1 still has :x
    assert TwoPhaseSet.member?(n1, :x) == true

    # After merge, n1 learns about the tombstone
    TwoPhaseSet.merge(n1, TwoPhaseSet.state(n2))
    assert TwoPhaseSet.member?(n1, :x) == false

    # And :x can never be re-added on n1
    assert_raise ArgumentError, fn ->
      TwoPhaseSet.add(n1, :x)
    end
  end