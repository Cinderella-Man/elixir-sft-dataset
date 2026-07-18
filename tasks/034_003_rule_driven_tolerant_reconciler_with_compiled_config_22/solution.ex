  @doc """
  Summarises how often each field differed across the matched pairs of a report.

  Returns a map of `%{field => number_of_matched_pairs_where_it_differed}`. Fields that
  never differed are omitted, so an all-clean report yields `%{}`.

  ## Examples

      iex> {:ok, config} = TolerantReconciler.compile(key_fields: [:id])
      iex> report = TolerantReconciler.run(config, [%{id: 1, name: "a"}], [%{id: 1, name: "b"}])
      iex> TolerantReconciler.field_summary(report)
      %{name: 1}
  """
  @spec field_summary(report()) :: %{optional(field()) => pos_integer()}
  def field_summary(%{matched: matched}) when is_list(matched) do
    Enum.reduce(matched, %{}, fn %{differences: differences}, acc ->
      Enum.reduce(Map.keys(differences), acc, fn field, inner ->
        Map.update(inner, field, 1, &(&1 + 1))
      end)
    end)
  end