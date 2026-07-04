  test "stage_stats executions reflect early halting" do
    guard = fn v -> if v == 3, do: {:error, :bad}, else: {:ok, v} end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:inc, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:guard, guard)
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, report} = Pipeline.run(pipeline, [1, 2, 3])

    stats = Map.new(report.stage_stats, fn s -> {s.stage, s.executions} end)
    assert stats == %{inc: 3, guard: 3, double: 2}
  end