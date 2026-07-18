  @spec hash_for(algorithm()) :: :sha | :sha256 | :sha512
  defp hash_for(:sha1), do: :sha
  defp hash_for(:sha256), do: :sha256
  defp hash_for(:sha512), do: :sha512