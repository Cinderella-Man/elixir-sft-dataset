@doc "Returns the current monotonic value converted to `unit`."
@spec monotonic(GenServer.server(), System.time_unit()) :: integer()
def monotonic(server, unit \\ :millisecond), do: GenServer.call(server, {:monotonic, unit})