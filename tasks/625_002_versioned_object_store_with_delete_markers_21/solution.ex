  @spec build_version(binary(), map(), boolean()) :: map()
  defp build_version(data, metadata, is_delete_marker) do
    %{
      version_id: generate_version_id(),
      is_delete_marker: is_delete_marker,
      data: data,
      metadata: metadata,
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }
  end