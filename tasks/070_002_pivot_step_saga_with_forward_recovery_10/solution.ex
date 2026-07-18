  defp run([], _completed, context), do: {:ok, context}

  defp run(
         [%{kind: :compensable, name: name, action: action} = step | rest],
         completed,
         context
       ) do
    case safe(action, context) do
      {:ok, result} ->
        run(rest, [step | completed], Map.put(context, name, result))

      {:error, reason} ->
        {:error, name, reason, compensate_all(completed, context)}
    end
  end

  defp run(
         [%{kind: :retriable, name: name, action: action, max_attempts: max} | rest],
         completed,
         context
       ) do
    case attempt(action, context, max, 1) do
      {:ok, result} ->
        run(rest, completed, Map.put(context, name, result))

      {:error, reason} ->
        {:error, name, {:retries_exhausted, reason}, []}
    end
  end