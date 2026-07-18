  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end