  defp enqueue_all(queue, items) do
    Enum.reduce(items, queue, fn item, q -> :queue.in(item, q) end)
  end