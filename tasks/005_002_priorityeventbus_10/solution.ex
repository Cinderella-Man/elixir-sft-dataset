  @doc "Convenience: cancel further delivery using the `reply_to` from an event."
  @spec cancel({pid(), reference()}) :: :ok
  def cancel({bus_pid, ref}) when is_pid(bus_pid) and is_reference(ref) do
    send(bus_pid, {:cancel, ref})
    :ok
  end