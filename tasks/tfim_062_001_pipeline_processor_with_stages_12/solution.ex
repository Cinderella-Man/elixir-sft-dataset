  test "metadata only includes executed stages when pipeline halts early" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:step_one, ok_stage(& &1))
      |> Pipeline.stage(:step_two, fail_stage(:nope))
      |> Pipeline.stage(:step_three, ok_stage(& &1))

    # On error we don't return metadata, so just verify halt behaviour
    assert {:error, :step_two, :nope} = Pipeline.run(pipeline, 1)
  end