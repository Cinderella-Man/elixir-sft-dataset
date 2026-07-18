  # Returns the GenServer pid stored at startup — works whether the server
  # was registered by name or started anonymously.
  defp server, do: :persistent_term.get(@pt_server)