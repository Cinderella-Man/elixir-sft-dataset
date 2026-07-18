  defp assemble(dup_ids, missing_ids, orphan_ids, cycles) do
    []
    |> maybe_add(dup_ids, :duplicate_id)
    |> maybe_add(missing_ids, :missing_parent_id)
    |> maybe_add(orphan_ids, :orphan)
    |> Kernel.++(Enum.map(cycles, fn cycle -> %{type: :cycle, ids: cycle} end))
  end