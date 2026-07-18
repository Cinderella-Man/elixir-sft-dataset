  def decline_invite(server, team_id, user_id) do
    GenServer.call(server, {:decline_invite, team_id, user_id})
  end