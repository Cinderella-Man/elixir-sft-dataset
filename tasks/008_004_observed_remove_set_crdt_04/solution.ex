  @spec element_present?(or_state(), element()) :: boolean()
  defp element_present?(%{entries: entries}, element) do
    case Map.fetch(entries, element) do
      {:ok, tags} -> MapSet.size(tags) > 0
      :error -> false
    end
  end