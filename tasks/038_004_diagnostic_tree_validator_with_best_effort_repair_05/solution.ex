  def build([]), do: {:ok, []}

  def build(items) when is_list(items) do
    {normalized, missing_pid_ids} = normalize(items)
    {deduped, dup_ids} = dedup(normalized)
    {cycles, acyclic} = extract_cycles(deduped)

    known = MapSet.new(Enum.map(acyclic, & &1.id))

    orphan_ids =
      for item <- acyclic,
          not is_nil(item.parent_id),
          not MapSet.member?(known, item.parent_id),
          do: item.id

    forest = build_forest(acyclic, known)
    issues = assemble(dup_ids, missing_pid_ids, orphan_ids, cycles)

    case issues do
      [] -> {:ok, forest}
      _ -> {:issues, forest, issues}
    end
  end