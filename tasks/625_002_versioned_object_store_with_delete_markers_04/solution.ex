  defp with_bucket(state, bucket, fun) do
    case fetch_bucket(state, bucket) do
      {:ok, keys} ->
        {reply, new_keys} = fun.(keys)
        persist_bucket(state.root_dir, bucket, new_keys)
        {:reply, reply, put_in(state.buckets[bucket], new_keys)}

      error ->
        {:reply, error, state}
    end
  end