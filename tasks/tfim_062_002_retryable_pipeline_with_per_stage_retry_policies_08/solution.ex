  test "default retries is zero (single attempt)" do
    pipeline = Pipeline.new() |> Pipeline.stage(:x, always_fail(:boom))
    assert {:error, :x, :boom, 1} = Pipeline.run(pipeline, 1)
  end