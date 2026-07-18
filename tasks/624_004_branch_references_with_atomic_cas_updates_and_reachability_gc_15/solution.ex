  @spec hash_content(binary()) :: hash
  defp hash_content(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end