  test "array/2 accepts max_length 0 and then only produces the empty list" do
    lists =
      Enum.map(1..50, fn seed ->
        [list] =
          JsonGenerators.array(JsonGenerators.scalar(), 0)
          |> StreamData.resize(20)
          |> StreamData.seeded(seed)
          |> Enum.take(1)

        list
      end)

    assert Enum.all?(lists, &(&1 == []))
  end