  @spec new_team() :: %{members: MapSet.t(String.t()), invitations: MapSet.t(String.t())}
  defp new_team do
    %{members: MapSet.new(), invitations: MapSet.new()}
  end