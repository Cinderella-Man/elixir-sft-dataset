  defp partition_stale(queue, now, threshold) do
    list = :queue.to_list(queue)

    {stale, fresh} =
      Enum.split_with(list, fn {_ref, _pid, _func, enqueued_at} ->
        now - enqueued_at >= threshold
      end)

    {stale, :queue.from_list(fresh)}
  end