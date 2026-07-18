  test "counts reports entry counts per category plus ambiguous total" do
    left = [
      %{id: 1, v: 1},
      %{id: 2, v: 1},
      %{id: 3, v: 1},
      %{id: 3, v: 2},
      %{id: 4, v: 1},
      %{id: 4, v: 2},
      %{id: 5, v: 1}
    ]

    right = [
      %{id: 1, v: 1},
      %{id: 2, v: 1},
      %{id: 2, v: 2},
      %{id: 3, v: 9},
      %{id: 4, v: 8},
      %{id: 4, v: 7},
      %{id: 6, v: 1}
    ]

    report = MultiKeyReconciler.classify(left, right, key_fields: [:id])
    counts = MultiKeyReconciler.counts(report)

    # id 1 -> 1:1, id 2 -> 1:many, id 3 -> many:1, id 4 -> many:many,
    # id 5 -> only left, id 6 -> only right
    assert counts.one_to_one == 1
    assert counts.one_to_many == 1
    assert counts.many_to_one == 1
    assert counts.many_to_many == 1
    assert counts.only_in_left == 1
    assert counts.only_in_right == 1
    assert counts.ambiguous == 3
  end