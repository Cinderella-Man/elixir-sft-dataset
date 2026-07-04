  test "single successful stage with no retries has attempts: 1" do
    pipeline = Pipeline.new() |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, 84, [%{stage: :double, attempts: 1, duration_us: d}]} =
             Pipeline.run(pipeline, 42)

    assert is_integer(d) and d >= 0
  end