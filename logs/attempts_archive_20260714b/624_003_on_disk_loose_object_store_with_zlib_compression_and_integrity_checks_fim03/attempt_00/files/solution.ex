  defp object_path(dir, hash) do
    <<prefix::binary-size(2), rest::binary>> = hash
    Path.join([dir, prefix, rest])
  end