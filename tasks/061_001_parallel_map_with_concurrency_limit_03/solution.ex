  # Trapped exits from finished/crashed tasks land in our mailbox; drain them
  # so pmap leaves the caller's mailbox exactly as it found it.
  defp flush_exit_messages do
    receive do
      {:EXIT, _pid, _reason} -> flush_exit_messages()
    after
      0 -> :ok
    end
  end
