  @spec do_put_object(
          state(),
          bucket(),
          %{optional(key()) => object()},
          key(),
          binary(),
          keyword()
        ) :: {:reply, {:ok, etag()} | {:error, :precondition_failed}, state()}
  defp do_put_object(state, bucket, objects, key, data, opts) do
    if put_precondition_met?(objects, key, opts) do
      object = build_object(data)
      new_objects = Map.put(objects, key, object)
      new_state = put_in(state.buckets[bucket], new_objects)
      {:reply, {:ok, object.etag}, new_state}
    else
      {:reply, {:error, :precondition_failed}, state}
    end
  end