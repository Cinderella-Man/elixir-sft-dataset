  # Builds a map of composite_key => record for fast O(1) lookups.
  # The composite key is a tuple of the values at the key fields in order,
  # e.g. {org_id_val, user_id_val}.  A single-field key uses a 1-tuple so
  # the representation is uniform and avoids collisions with plain values.
  @spec index_by([record_t()], [atom()]) :: %{tuple() => record_t()}
  defp index_by(records, key_fields) do
    Map.new(records, fn record ->
      {composite_key(record, key_fields), record}
    end)
  end