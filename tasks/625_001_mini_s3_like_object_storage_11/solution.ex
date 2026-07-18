  defp object_data_path(state, bucket, key) do
    Path.join(objects_dir(state, bucket), encode_key(key) <> ".data")
  end