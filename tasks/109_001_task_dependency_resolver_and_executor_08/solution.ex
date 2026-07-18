  @impl true
  def init(_state) do
    # state is a map: task_id => %{depends_on: [...], func: fun}
    {:ok, %{}}
  end