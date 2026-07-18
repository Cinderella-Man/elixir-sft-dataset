  defp check_readable(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> {:ok, :regular}
      {:ok, %File.Stat{type: :directory}} -> {:error, :eisdir}
      {:ok, %File.Stat{type: _other}} -> {:error, :einval}
      {:error, reason} -> {:error, reason}
    end
  end