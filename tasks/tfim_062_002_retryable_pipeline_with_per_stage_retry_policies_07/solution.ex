  test "exhausting the retry budget halts with the attempts count" do
    pipeline = Pipeline.new() |> Pipeline.stage(:x, always_fail(:nope), retries: 2)
    assert {:error, :x, :nope, 3} = Pipeline.run(pipeline, 1)
  end