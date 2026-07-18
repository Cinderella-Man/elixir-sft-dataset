  test "queries stay correct after interleaved inserts and deletes at scale" do
    tree =
      Enum.reduce(0..199, T.new(), fn i, acc ->
        T.insert(acc, {i * 10, i * 10 + 9})
      end)

    assert T.size(tree) == 200

    # Delete every even-indexed interval.
    tree =
      Enum.reduce(0..199//2, tree, fn i, acc ->
        {:ok, acc2} = T.delete(acc, {i * 10, i * 10 + 9})
        acc2
      end)

    assert T.size(tree) == 100

    # {90,99} was even-indexed (i=9? -> 9 is odd, kept). Verify a kept one.
    assert T.member?(tree, {90, 99})
    # {100,109} is i=10 (even) -> deleted
    refute T.member?(tree, {100, 109})

    # Overlap query that would have touched three intervals now touches two kept ones.
    result = T.overlapping(tree, {95, 115})
    assert {90, 99} in result
    refute {100, 109} in result
    assert {110, 119} in result

    # Point query on a kept interval.
    assert [{150, 159}] = T.enclosing(tree, 155)
  end