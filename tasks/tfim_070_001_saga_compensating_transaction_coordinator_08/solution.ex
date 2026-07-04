  test "compensations receive the enriched context at the point of failure" do
    Saga.new()
    |> Saga.step(:step_a, fn _ctx -> {:ok, :a_result} end, fn ctx ->
      track(:comp_ctx, ctx)
    end)
    |> Saga.step(:step_b, fn _ctx -> {:error, :fail} end, fn _ctx -> nil end)
    |> Saga.execute(%{seed: :value})

    [ctx] = tracked(:comp_ctx)
    # Context should include original seed and the result of step_a
    assert ctx.seed == :value
    assert ctx.step_a == :a_result
  end