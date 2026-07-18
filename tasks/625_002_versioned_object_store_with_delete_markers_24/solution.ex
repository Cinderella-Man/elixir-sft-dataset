  @spec summarize(map()) :: version_summary()
  defp summarize(version) do
    %{
      version_id: version.version_id,
      is_delete_marker: version.is_delete_marker,
      size: version.size,
      last_modified: version.last_modified
    }
  end