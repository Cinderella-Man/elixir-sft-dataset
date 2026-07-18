  test "multiple failures are listed in input index order" do
    guard = fn v -> if rem(v, 2) == 0, do: {:error, {:even, v}}, else: {:ok, v} end

    pipeline = Pipeline.new() |> Pipeline.stage(:parity, guard)

    assert {:ok, report} = Pipeline.run(pipeline, [2, 1, 4, 3, 6])

    assert report.failures == [
             %{index: 0, stage: :parity, reason: {:even, 2}},
             %{index: 2, stage: :parity, reason: {:even, 4}},
             %{index: 4, stage: :parity, reason: {:even, 6}}
           ]

    assert report.successes == [%{index: 1, result: 1}, %{index: 3, result: 3}]
  end