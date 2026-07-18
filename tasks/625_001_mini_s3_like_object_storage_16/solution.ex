  defp object_summary(state, bucket, key) do
    meta_path = object_meta_path(state, bucket, key)
    meta = meta_path |> File.read!() |> :erlang.binary_to_term()

    %{
      key: key,
      size: meta.size,
      last_modified: meta.last_modified
    }
  end