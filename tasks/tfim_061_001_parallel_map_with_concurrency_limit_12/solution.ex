  test "all items crash — returns all error tuples" do
    results = ParallelMap.pmap([1, 2, 3], fn _ -> raise "always" end, 2)

    assert length(results) == 3
    assert Enum.all?(results, &match?({:error, _}, &1))
  end