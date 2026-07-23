  test "backoff_ms defaults to zero so retries run back to back" do
    pipeline = Pipeline.new() |> Pipeline.stage(:x, always_fail(:boom), retries: 20)

    {elapsed_us, result} = :timer.tc(fn -> Pipeline.run(pipeline, :in) end)

    assert {:error, :x, :boom, 21} = result
    # Twenty instant retries with the default zero backoff cost no wall time.
    assert elapsed_us < 1_000_000
  end