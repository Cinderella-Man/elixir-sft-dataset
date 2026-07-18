  # Sorted insert: descending priority, then ascending subscription order (seq).
  defp insert_sorted(list, sub) do
    # `list` already has `sub` filtered out (see caller).  Prepend and sort —
    # the list is typically small so this is fine.
    [sub | list]
    |> Enum.uniq_by(& &1.ref)
    |> Enum.sort_by(fn %{priority: p, seq: s} -> {-p, s} end)
  end