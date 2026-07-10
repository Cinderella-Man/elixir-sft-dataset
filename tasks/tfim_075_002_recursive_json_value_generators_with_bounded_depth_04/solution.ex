  test "scalar strings attain the documented 8-char maximum across seeded samples" do
    lengths =
      Enum.map(1..300, fn seed ->
        [v] =
          JsonGenerators.scalar()
          |> StreamData.resize(20)
          |> StreamData.seeded(seed)
          |> Enum.take(1)

        if is_binary(v), do: String.length(v), else: -1
      end)

    assert Enum.max(lengths) == 8
  end