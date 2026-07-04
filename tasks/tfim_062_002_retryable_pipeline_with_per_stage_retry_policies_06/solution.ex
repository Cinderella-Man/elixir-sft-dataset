  test "a flaky stage succeeds after retries and reports attempts" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 3, do: {:error, :flaky}, else: {:ok, v * 10}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, flaky, retries: 5)

    assert {:ok, 20, [%{stage: :s, attempts: 3}]} = Pipeline.run(pipeline, 2)
  end