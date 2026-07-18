  @spec put_bucket(map(), String.t(), map()) :: map()
  defp put_bucket(state, bucket, objects) do
    %{state | buckets: Map.put(state.buckets, bucket, objects)}
  end