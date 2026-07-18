  @spec ensure_agent_started() :: :ok
  defp ensure_agent_started do
    case Process.whereis(@agent) do
      nil ->
        Agent.start_link(fn -> %{} end, name: @agent)
        :ok

      _pid ->
        :ok
    end
  end