  # Compensates a fully-succeeded saga: every step, in reverse order.
  defp compensate_full(steps, ctx) do
    steps
    |> Enum.reverse()
    |> Enum.map(fn
      %{kind: :leaf, name: name, compensate: comp} ->
        {name, safe_compensate(comp, ctx)}

      %{kind: :nested, name: name, saga: sub} ->
        {name, compensate_full(sub.steps, Map.get(ctx, name, ctx))}
    end)
  end