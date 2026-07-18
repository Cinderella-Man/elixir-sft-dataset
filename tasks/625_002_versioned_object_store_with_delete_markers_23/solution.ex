  defp fetch_version(keys, key, version_id) do
    versions = Map.get(keys, key, [])

    case Enum.find(versions, &(&1.version_id == version_id)) do
      nil ->
        {:error, :not_found}

      version ->
        {:ok,
         %{
           data: version.data,
           metadata: version.metadata,
           size: version.size,
           version_id: version.version_id,
           is_delete_marker: version.is_delete_marker,
           last_modified: version.last_modified
         }}
    end
  end