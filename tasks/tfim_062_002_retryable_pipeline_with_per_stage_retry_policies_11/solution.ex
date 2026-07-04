  test "backoff option still succeeds within budget" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :again}, else: {:ok, v + 1}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, flaky, retries: 3, backoff_ms: 2)
    assert {:ok, 6, [%{attempts: 2}]} = Pipeline.run(pipeline, 5)
  end