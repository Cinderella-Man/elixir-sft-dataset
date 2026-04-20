def handle_call({:release, bucket_name, lease_id, outcome}, _from, state) do
  case Map.fetch(state.buckets, bucket_name) do
    :error ->
      {:reply, {:error, :unknown_lease}, state}

    {:ok, bucket} ->
      now = state.clock.()
      bucket = refill_and_expire(bucket, now)

      case Map.fetch(bucket.leases, lease_id) do
        :error ->
          # Lease was either never issued, already released, or expired
          # during refill_and_expire above.
          {:reply, {:error, :unknown_lease},
            %{state | buckets: Map.put(state.buckets, bucket_name, bucket)}}

        {:ok, {tokens, _expires_at}} ->
          new_bucket =
            case outcome do
              :completed ->
                %{bucket | leases: Map.delete(bucket.leases, lease_id)}

              :cancelled ->
                refunded = min(bucket.capacity * 1.0, bucket.free + tokens)

                %{
                  bucket
                  | free: refunded,
                    leases: Map.delete(bucket.leases, lease_id)
                }
            end

          {:reply, :ok,
            %{state | buckets: Map.put(state.buckets, bucket_name, new_bucket)}}
      end
  end
end
