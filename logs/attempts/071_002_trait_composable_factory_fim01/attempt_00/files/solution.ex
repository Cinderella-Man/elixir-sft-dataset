def build(name, traits, overrides) when is_list(traits) and is_list(overrides) do
  trait_overlay = Enum.flat_map(traits, fn t -> trait(name, t) end)

  name
  |> factory()
  |> merge(trait_overlay)
  |> merge(overrides)
  |> resolve_thunks()
end