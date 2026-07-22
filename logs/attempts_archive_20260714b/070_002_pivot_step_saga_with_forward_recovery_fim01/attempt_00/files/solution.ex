  defp attempt(action, context, max, n) do
    case safe(action, context) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        if n >= max, do: {:error, reason}, else: attempt(action, context, max, n + 1)
    end
  end