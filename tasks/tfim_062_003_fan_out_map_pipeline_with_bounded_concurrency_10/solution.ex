  test "max_concurrency: 1 serializes element processing" do
    slow = fn x ->
      Process.sleep(20)
      {:ok, x}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:slow, slow, max_concurrency: 1)

    assert {:ok, _, [%{stage: :slow, duration_us: d}]} = Pipeline.run(pipeline, [1, 2, 3])
    assert d >= 30_000
  end