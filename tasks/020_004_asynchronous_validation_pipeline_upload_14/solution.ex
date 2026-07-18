  defp validate_json(path) do
    case Jason.decode(File.read!(path)) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end