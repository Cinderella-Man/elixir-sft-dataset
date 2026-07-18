  @spec load_buckets(String.t()) :: map()
  defp load_buckets(root) do
    case File.ls(root) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, @bucket_suffix))
        |> Enum.reduce(%{}, fn file, acc -> load_bucket_file(root, file, acc) end)

      _error ->
        %{}
    end
  end