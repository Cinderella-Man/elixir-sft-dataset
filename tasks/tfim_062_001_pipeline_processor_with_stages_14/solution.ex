  test "a stage that sleeps produces a duration_us greater than sleep time" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:slow, fn v ->
        Process.sleep(10)
        {:ok, v}
      end)

    assert {:ok, _, [%{stage: :slow, duration_us: d}]} = Pipeline.run(pipeline, 1)
    # 10 ms = 10_000 µs; allow a small margin
    assert d >= 9_000
  end