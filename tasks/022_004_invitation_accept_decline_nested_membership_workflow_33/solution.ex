  @doc """
  Creates a pending invitation for `user_id` on the given team.

  Returns `{:error, :not_found}` if the team does not exist,
  `{:error, :conflict}` if the user is already an active member,
  `{:error, :already_invited}` if the user already has a pending invitation,
  and `{:ok, user_id}` on success.
  """
  @spec invite_member(server(), String.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, :not_found | :conflict | :already_invited}
  def invite_member(server, team_id, user_id) do
    GenServer.call(server, {:invite_member, team_id, user_id})
  end