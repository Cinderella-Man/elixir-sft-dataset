  defp fetch_bucket(state, bucket) do
    case Map.fetch(state.buckets, bucket) do
      {:ok, keys} -> {:ok, keys}
      :error -> {:error, :bucket_not_found}
    end
  end