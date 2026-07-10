  test "object/2 accepts max_length 0 and then only produces the empty map" do
    maps =
      Enum.map(1..50, fn seed ->
        [obj] =
          JsonGenerators.object(JsonGenerators.scalar(), 0)
          |> StreamData.resize(20)
          |> StreamData.seeded(seed)
          |> Enum.take(1)

        obj
      end)

    assert Enum.all?(maps, &(&1 == %{}))
  end