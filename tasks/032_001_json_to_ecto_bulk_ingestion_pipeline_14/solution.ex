  # Accepts both atom-keyed structs/maps and string-keyed plain maps.
  @spec get_ts(map() | struct(), atom()) :: NaiveDateTime.t() | DateTime.t() | nil
  defp get_ts(row, field) when is_map(row) do
    Map.get(row, field) || Map.get(row, Atom.to_string(field))
  end