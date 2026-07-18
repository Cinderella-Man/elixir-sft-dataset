  # Build the struct and return {struct, [persisted association structs]} so the
  # caller can compensate (delete) them if validation fails.
  defp build_with_assocs(name, overrides) do
    name
    |> factory()
    |> merge_overrides(overrides)
    |> resolve_assocs()
  end