  @impl GenServer
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, %{tables: %{}}}
  end