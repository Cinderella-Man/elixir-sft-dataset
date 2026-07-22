  defp run([], _completed, context), do: {:ok, context}

  defp run(
         [%{kind: :leaf, name: name, action: action, compensate: comp} | rest],
         completed,
         ctx
       ) do
    case safe(action, ctx) do
      {:ok, result} ->
        done = %{kind: :leaf, name: name, compensate: comp}
        run(rest, [done | completed], Map.put(ctx, name, result))

      {:error, reason} ->
        {:error, [name], reason, compensate_all(completed, ctx)}
    end
  end

  defp run([%{kind: :nested, name: name, saga: sub} | rest], completed, ctx) do
    case execute(sub, ctx) do
      {:ok, sub_ctx} ->
        done = %{kind: :nested, name: name, saga: sub, ctx: sub_ctx}
        run(rest, [done | completed], Map.put(ctx, name, sub_ctx))

      {:error, sub_path, reason, sub_comp} ->
        # The sub-saga already unwound its own completed steps; propagate and
        # then compensate this saga's previously completed steps.
        outer = compensate_all(completed, ctx)
        {:error, [name | sub_path], reason, [{name, sub_comp} | outer]}
    end
  end