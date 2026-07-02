  test "single stage runs and returns ok with metadata" do
    pipeline = Pipeline.new() |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, 84, metadata} = Pipeline.run(pipeline, 42)
    assert length(metadata) == 1
    assert [%{stage: :double, duration_us: d}] = metadata
    assert is_integer(d) and d >= 0
  end