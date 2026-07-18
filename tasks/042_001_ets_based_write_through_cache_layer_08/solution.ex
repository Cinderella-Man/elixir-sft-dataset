  @impl GenServer
  def init(:ok) do
    # Trap exits so `terminate/2` is reliably called, giving us a chance to
    # clean up :persistent_term entries even if the supervisor shuts us down.
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}}}
  end