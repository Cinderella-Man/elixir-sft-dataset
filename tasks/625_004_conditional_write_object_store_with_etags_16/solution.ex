  defp fetch_bucket(state, bucket) do
    case Map.fetch(state.buckets, bucket) do
      {:ok, objects} -> {:ok, objects}
      :error -> {:error, :bucket_not_found}
    end
  end