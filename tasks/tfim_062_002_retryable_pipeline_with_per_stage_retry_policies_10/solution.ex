  test "duration accumulates across attempts" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    slow_flaky = fn v ->
      Process.sleep(5)
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 3, do: {:error, :retry}, else: {:ok, v}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, slow_flaky, retries: 5)

    assert {:ok, 7, [%{attempts: 3, duration_us: d}]} = Pipeline.run(pipeline, 7)
    # 3 attempts sleeping ~5ms each
    assert d >= 10_000
  end