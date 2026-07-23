  test "a stage that succeeds on its first attempt never pays its backoff" do
    backoff_ms = 5_000

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fast, ok_stage(&(&1 * 2)), retries: 3, backoff_ms: backoff_ms)

    {elapsed_us, result} = :timer.tc(fn -> Pipeline.run(pipeline, 21) end)

    assert {:ok, 42, [%{stage: :fast, attempts: 1}]} = result
    # Backoff separates attempts; with a single attempt there is nothing to
    # separate, so the run must finish far below one backoff period.
    assert elapsed_us < 1_000_000
  end