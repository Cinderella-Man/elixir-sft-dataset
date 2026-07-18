  test "backoff_ms is honoured before a retry that ultimately succeeds" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)
    backoff_ms = 60

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :again}, else: {:ok, v + 1}
    end

    pipeline =
      Pipeline.new() |> Pipeline.stage(:s, flaky, retries: 3, backoff_ms: backoff_ms)

    {elapsed_us, result} = :timer.tc(fn -> Pipeline.run(pipeline, 5) end)

    assert {:ok, 6, [%{stage: :s, attempts: 2}]} = result
    # Two attempts means exactly one backoff sleep separates them.
    assert elapsed_us >= backoff_ms * 1_000
  end