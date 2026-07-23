  test "one backoff sleep per retry used, so total wait scales with the retry count" do
    backoff_ms = 40
    retries = 3

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:x, always_fail(:nope), retries: retries, backoff_ms: backoff_ms)

    {elapsed_us, result} = :timer.tc(fn -> Pipeline.run(pipeline, :in) end)

    assert {:error, :x, :nope, 4} = result
    # Four attempts of an instant function are separated by three sleeps, so
    # the run cannot finish faster than three whole backoff periods.
    assert elapsed_us >= retries * backoff_ms * 1_000
  end