  @doc "Subscribes `pid` to `topic`, optionally replaying buffered events. Returns `{:ok, ref}`."
  @spec subscribe(GenServer.server(), String.t(), pid(), keyword()) :: {:ok, reference()}
  def subscribe(server, topic, pid, opts \\ [])
      when is_binary(topic) and is_pid(pid) and is_list(opts) do
    GenServer.call(server, {:subscribe, topic, pid, opts})
  end