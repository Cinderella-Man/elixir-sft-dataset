  test "map stage preserves input order in its output" do
    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:id, fn x -> {:ok, x} end)

    assert {:ok, [5, 3, 9, 1], _} = Pipeline.run(pipeline, [5, 3, 9, 1])
  end