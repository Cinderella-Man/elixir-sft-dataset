  # Top-level filter: list of clauses, all must match.
  defp eval_filter(filter, event) do
    Enum.all?(filter, &eval_clause(&1, event))
  end