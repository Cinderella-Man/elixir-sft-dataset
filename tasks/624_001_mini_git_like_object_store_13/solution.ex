  defp sha1(content) do
    :crypto.hash(:sha, content)
    |> Base.encode16(case: :lower)
  end