  @spec current_objects(map()) :: [map()]
  defp current_objects(keys) do
    keys
    |> Enum.reduce([], fn {key, versions}, acc ->
      case versions do
        [%{is_delete_marker: false} = version | _rest] ->
          entry = %{
            key: key,
            size: version.size,
            version_id: version.version_id,
            last_modified: version.last_modified
          }

          [entry | acc]

        _other ->
          acc
      end
    end)
    |> Enum.sort_by(& &1.key)
  end