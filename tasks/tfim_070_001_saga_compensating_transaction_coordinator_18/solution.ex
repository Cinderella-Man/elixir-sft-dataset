  test "every compensation sees the same context including all completed step results" do
    Saga.new()
    |> Saga.step(:alpha, fn _ctx -> {:ok, :a_val} end, fn ctx -> track(:ctxs, ctx) end)
    |> Saga.step(:beta, fn _ctx -> {:ok, :b_val} end, fn ctx -> track(:ctxs, ctx) end)
    |> Saga.step(:gamma, fn _ctx -> {:error, :bad} end, fn ctx -> track(:ctxs, ctx) end)
    |> Saga.execute(%{seed: 0})

    [beta_ctx, alpha_ctx] = tracked(:ctxs)
    expected = %{seed: 0, alpha: :a_val, beta: :b_val}
    assert beta_ctx == expected
    assert alpha_ctx == expected
  end