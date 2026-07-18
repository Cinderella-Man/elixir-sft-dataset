  test "repeated merges after continued operations converge", %{} do
    {:ok, n1} = Counter.start_link([])
    {:ok, n2} = Counter.start_link([])

    # Round 1
    Counter.increment(n1, :n1, 3)
    Counter.increment(n2, :n2, 4)

    s1 = Counter.state(n1)
    s2 = Counter.state(n2)
    Counter.merge(n1, s2)
    Counter.merge(n2, s1)
    assert Counter.value(n1) == 7
    assert Counter.value(n2) == 7

    # Round 2: more operations after merge
    Counter.increment(n1, :n1, 2)
    Counter.decrement(n2, :n2, 1)

    s1 = Counter.state(n1)
    s2 = Counter.state(n2)
    Counter.merge(n1, s2)
    Counter.merge(n2, s1)

    # n1 increments: 3+2=5, n2 increments: 4, n2 decrements: 1
    # value = 5 + 4 - 1 = 8
    assert Counter.value(n1) == 8
    assert Counter.value(n2) == 8
  end