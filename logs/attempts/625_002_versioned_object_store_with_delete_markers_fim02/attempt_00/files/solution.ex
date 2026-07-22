  @spec latest_object(map(), String.t()) ::
          {:ok, map()} | {:error, :not_found}
  defp latest_object(keys, key) do
    case Map.get(keys, key, []) do
      [%{is_delete_marker: false} = version | _rest] ->
        {:ok,
         %{
           data: version.data,
           metadata: version.metadata,
           size: version.size,
           version_id: version.version_id,
           last_modified: version.last_modified
         }}

      _other ->
        {:error, :not_found}
    end
  end