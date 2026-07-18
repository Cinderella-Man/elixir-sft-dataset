  @spec sha1_hex(binary()) :: hash()
  defp sha1_hex(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end