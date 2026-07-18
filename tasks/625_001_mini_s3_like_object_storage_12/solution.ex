  defp object_meta_path(state, bucket, key) do
    Path.join(objects_dir(state, bucket), encode_key(key) <> ".meta")
  end