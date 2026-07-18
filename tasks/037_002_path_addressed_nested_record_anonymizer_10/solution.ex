  @doc """
  Anonymizes `records` (a list of possibly deeply nested maps) according to
  `rules`, a map of string paths to rule atoms/tuples.

  Returns a list of the same length and structure, with addressed values
  transformed in place. Paths that do not resolve in a given record are
  skipped gracefully.
  """
  @spec anonymize([map()], %{optional(String.t()) => term()}) :: [map()]
  def anonymize(records, rules) when is_list(records) and is_map(rules) do
    compiled = Enum.map(rules, fn {path, rule} -> {parse_path(path), rule} end)

    Enum.map(records, fn record ->
      Enum.reduce(compiled, record, fn {segments, rule}, acc ->
        update_path(acc, segments, rule)
      end)
    end)
  end