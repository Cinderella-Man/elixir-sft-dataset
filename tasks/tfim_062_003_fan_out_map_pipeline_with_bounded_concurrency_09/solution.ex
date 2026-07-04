  test "map stage runs elements concurrently" do
    slow = fn x ->
      Process.sleep(20)
      {:ok, x}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:slow, slow, max_concurrency: 4)

    assert {:ok, [1, 2, 3, 4], [%{stage: :slow, duration_us: d}]} =
             Pipeline.run(pipeline, [1, 2, 3, 4])

    # 4 * 20ms serial would be ~80ms; concurrent should be far below.
    assert d < 90_000
  end