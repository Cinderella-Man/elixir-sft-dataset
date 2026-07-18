  defp read_object(state, bucket, key) do
    data_path = object_data_path(state, bucket, key)
    meta_path = object_meta_path(state, bucket, key)

    data = File.read!(data_path)
    meta = meta_path |> File.read!() |> :erlang.binary_to_term()

    %{
      data: data,
      content_type: meta.content_type,
      metadata: meta.metadata,
      size: meta.size,
      last_modified: meta.last_modified
    }
  end