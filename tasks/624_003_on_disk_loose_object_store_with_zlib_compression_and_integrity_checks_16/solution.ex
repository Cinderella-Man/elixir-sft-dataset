  @spec list_dir(String.t()) :: [String.t()]
  defp list_dir(dir) do
    case File.ls(dir) do
      {:ok, entries} -> entries
      {:error, _reason} -> []
    end
  end