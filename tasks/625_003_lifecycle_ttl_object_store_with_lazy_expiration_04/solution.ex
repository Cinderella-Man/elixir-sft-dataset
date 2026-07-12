def handle_call({:get_object, bucket, key}, _from, state) do
  case Map.fetch(state.buckets, bucket) do
    :error ->
      {:reply, {:error, :bucket_not_found}, state}

    {:ok, objects} ->
      now = now_ms()

      case Map.fetch(objects, key) do
        {:ok, obj} ->
          if expired?(obj, now) do
            objects = Map.delete(objects, key)
            {:reply, {:error, :not_found}, put_bucket(state, bucket, objects)}
          else
            reply = {:ok, Map.take(obj, [:data, :size, :last_modified])}
            {:reply, reply, state}
          end

        :error ->
          {:reply, {:error, :not_found}, state}
      end
  end
end