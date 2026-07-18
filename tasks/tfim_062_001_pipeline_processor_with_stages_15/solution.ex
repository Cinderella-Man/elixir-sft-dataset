  test "pipeline works with map input and output" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:enrich, ok_stage(&Map.put(&1, :enriched, true)))
      |> Pipeline.stage(:serialize, ok_stage(&Map.keys/1))

    assert {:ok, keys, _} = Pipeline.run(pipeline, %{a: 1})
    assert :enriched in keys
  end