  def log(server, commit_hash) when is_binary(commit_hash) do
    GenServer.call(server, {:log, commit_hash})
  end