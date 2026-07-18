  def list_invitations(server, team_id) do
    GenServer.call(server, {:list_invitations, team_id})
  end