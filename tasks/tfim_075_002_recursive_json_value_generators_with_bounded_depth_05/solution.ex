  test "value(2) attains the full depth of 2 across seeded samples" do
    depths =
      Enum.map(1..300, fn seed ->
        [v] =
          JsonGenerators.value(2)
          |> StreamData.resize(20)
          |> StreamData.seeded(seed)
          |> Enum.take(1)

        depth(v)
      end)

    assert Enum.max(depths) == 2
  end