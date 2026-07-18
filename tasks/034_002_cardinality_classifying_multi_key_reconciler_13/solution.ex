  @doc """
  Counts the entries of a report produced by `classify/3`.

  Returns a map with one count per report list, plus `:ambiguous`, the sum of the
  `:one_to_many`, `:many_to_one` and `:many_to_many` counts.
  """
  @spec counts(report()) :: %{optional(atom()) => non_neg_integer()}
  def counts(report) when is_map(report) do
    counts = Map.new(@report_keys, fn key -> {key, length(Map.fetch!(report, key))} end)

    ambiguous = counts.one_to_many + counts.many_to_one + counts.many_to_many

    Map.put(counts, :ambiguous, ambiguous)
  end