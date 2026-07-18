  @spec load_bucket_file(String.t(), String.t(), map()) :: map()
  defp load_bucket_file(root, file, acc) do
    name = String.replace_suffix(file, @bucket_suffix, "")

    case File.read(Path.join(root, file)) do
      {:ok, binary} -> Map.put(acc, name, :erlang.binary_to_term(binary))
      _error -> acc
    end
  end