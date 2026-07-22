  # `completed` is in reverse-execution order (most recent first).
  defp compensate_all(completed, ctx) do
    Enum.map(completed, fn
      %{kind: :leaf, name: name, compensate: comp} ->
        {name, safe_compensate(comp, ctx)}

      %{kind: :nested, name: name, saga: sub, ctx: sub_ctx} ->
        {name, compensate_full(sub.steps, sub_ctx)}
    end)
  end