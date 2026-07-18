  test "metadata reports non-negative integer durations for both stage types" do
    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:m, fn x -> {:ok, x} end)
      |> Pipeline.stage(:s, fn v -> {:ok, Enum.sum(v)} end)

    assert {:ok, 3, [map_meta, seq_meta]} = Pipeline.run(pipeline, [1, 2])
    assert is_integer(map_meta.duration_us) and map_meta.duration_us >= 0
    assert is_integer(seq_meta.duration_us) and seq_meta.duration_us >= 0
  end