  defp bucket_empty?(state, bucket) do
    obj_dir = objects_dir(state, bucket)

    case File.ls(obj_dir) do
      {:ok, []} -> true
      {:ok, _files} -> false
      {:error, :enoent} -> true
    end
  end