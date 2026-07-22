  defp write_object(state, bucket, key, data, content_type, metadata) do
    data_path = object_data_path(state, bucket, key)
    meta_path = object_meta_path(state, bucket, key)

    File.mkdir_p!(Path.dirname(data_path))

    meta = %{
      content_type: content_type,
      metadata: metadata,
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }

    File.write!(data_path, data)
    File.write!(meta_path, :erlang.term_to_binary(meta))
  end