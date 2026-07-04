  test "middle stage failing halts and returns correct stage name" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fetch, ok_stage(&(&1 <> "_fetched")))
      |> Pipeline.stage(:transform, fail_stage(:bad_data))
      |> Pipeline.stage(:load, ok_stage(&(&1 <> "_loaded")))

    assert {:error, :transform, :bad_data} = Pipeline.run(pipeline, "x")
  end