  @doc "Convenience: send an ack to the bus using the `reply_to` from an event."
  @spec ack({pid(), reference()}) :: :ok
  def ack({bus_pid, ref}) when is_pid(bus_pid) and is_reference(ref) do
    send(bus_pid, {:ack, ref})
    :ok
  end