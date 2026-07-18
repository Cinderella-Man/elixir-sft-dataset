  defp validate_json(path) do
    content = File.read!(path)

    case Jason.decode(content) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end