  @impl GenServer
  def terminate(_reason, state) do
    pid = self()

    # Delete each ETS table (which also frees its memory) and remove the
    # corresponding :persistent_term entry so stale tids cannot leak to callers
    # that somehow still hold a reference to this (now-dead) server.
    Enum.each(state.tables, fn {table, tid} ->
      :persistent_term.erase({__MODULE__, pid, table})
      :ets.delete(tid)
    end)

    :ok
  end