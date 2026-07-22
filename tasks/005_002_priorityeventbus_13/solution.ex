  # Sorted insert: descending priority, then ascending subscription order (seq).
  defp insert_sorted(list, sub) do
    # Prepend and sort — the list is typically small so this is fine. Every
    # entry carries its own globally-unique monitor ref, so entries can never
    # collide and no dedup or pre-filtering is needed.
    [sub | list]
    |> Enum.sort_by(fn %{priority: p, seq: s} -> {-p, s} end)
  end