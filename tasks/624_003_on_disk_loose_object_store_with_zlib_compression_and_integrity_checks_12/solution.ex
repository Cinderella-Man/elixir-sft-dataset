  @spec hash_hex(binary()) :: hash()
  defp hash_hex(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end