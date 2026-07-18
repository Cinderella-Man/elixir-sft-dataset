  def accept_invite(server, team_id, user_id) do
    GenServer.call(server, {:accept_invite, team_id, user_id})
  end