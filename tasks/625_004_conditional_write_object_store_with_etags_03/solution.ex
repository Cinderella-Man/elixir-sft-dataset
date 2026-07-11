  @spec etag(binary()) :: etag()
  defp etag(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end