  @doc """
  Fetches the value cached under `{table, key}`, computing it on a miss.

  On a cache hit the value is read directly from ETS with no GenServer
  round-trip. On a miss the caller joins the single-flight protocol: exactly one
  racing caller runs `fallback_fn`, the rest wait for and receive its result.
  Always returns `{:ok, value}`.
  """
  @spec fetch(GenServer.server(), atom(), term(), (-> term())) :: {:ok, term()}
  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        join_and_compute(server, table, key, fallback_fn)

      tid ->
        case :ets.lookup(tid, key) do
          [{^key, value}] -> {:ok, value}
          [] -> join_and_compute(server, table, key, fallback_fn)
        end
    end
  end