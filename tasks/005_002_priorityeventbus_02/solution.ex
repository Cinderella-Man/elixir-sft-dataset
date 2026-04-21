# Walks the list in order.  For each subscriber:
#   - Send {:event, topic, event, {self(), unique_ref}}
#   - Receive {:ack, unique_ref} | {:cancel, unique_ref} | timeout | :DOWN
#   - :ack / timeout / :DOWN continue; :cancel stops delivery.
defp deliver_serially([], _topic, _event, _timeout, delivered), do: delivered

defp deliver_serially([sub | rest], topic, event, timeout, delivered) do
  unique_ref = make_ref()
  reply_to = {self(), unique_ref}

  send(sub.pid, {:event, topic, event, reply_to})

  receive do
    {:ack, ^unique_ref} ->
      deliver_serially(rest, topic, event, timeout, delivered + 1)

    {:cancel, ^unique_ref} ->
      delivered + 1

    # If the subscriber dies mid-publish, its monitor fires; treat as :ack
    # and continue.  We don't consume the :DOWN here — we leave it for
    # the regular handle_info path so the cleanup still runs.
    {:DOWN, _ref, :process, pid, _reason} = down when pid == sub.pid ->
      # Re-queue for normal processing and continue.
      send(self(), down)
      deliver_serially(rest, topic, event, timeout, delivered + 1)
  after
    timeout ->
      deliver_serially(rest, topic, event, timeout, delivered + 1)
  end
end
