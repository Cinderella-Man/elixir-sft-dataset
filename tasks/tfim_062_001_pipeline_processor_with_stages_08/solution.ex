  test "first stage failing returns error with correct stage name and reason" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fetch, fail_stage(:timeout))
      |> Pipeline.stage(:transform, ok_stage(& &1))

    assert {:error, :fetch, :timeout} = Pipeline.run(pipeline, "input")
  end