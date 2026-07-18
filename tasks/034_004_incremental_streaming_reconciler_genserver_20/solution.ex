  @spec build_entry(state(), key(), stream_record(), stream_record()) :: entry()
  defp build_entry(state, key, left, right) do
    %{
      key: key_map(state.key_fields, key),
      left: left,
      right: right,
      differences: differences(state, left, right)
    }
  end