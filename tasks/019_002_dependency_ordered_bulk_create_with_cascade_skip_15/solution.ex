  defp build_results(indices, status, items) do
    Enum.map(indices, fn i ->
      case status[i] do
        :ok ->
          case Map.fetch(items, i) do
            {:ok, item} -> {i, :ok, item}
            :error -> {i, :ok, :valid}
          end

        {:bad, reason} ->
          {i, :error, reason}

        {:skipped, anc} ->
          {i, :skipped, anc}
      end
    end)
  end