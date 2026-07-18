  test "run/2 waits backoff_ms between attempts of a retried stage" do
    backoff_ms = 60
    retries = 2

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:x, always_fail(:nope), retries: retries, backoff_ms: backoff_ms)

    {elapsed_us, result} = :timer.tc(fn -> Pipeline.run(pipeline, 1) end)

    assert {:error, :x, :nope, 3} = result
    # 3 attempts of an instant function: the only time spent is the two
    # backoff sleeps that separate them.
    assert elapsed_us >= retries * backoff_ms * 1_000
  end