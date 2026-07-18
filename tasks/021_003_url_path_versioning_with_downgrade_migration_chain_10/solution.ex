  @doc """
  Renders `user` under `id` for the requested `version`.

  Builds the canonical v3 document and applies each downgrade step needed to
  reach `version`.
  """
  @spec render(String.t(), String.t(), map()) :: map()
  def render(version, id, user) do
    user
    |> canonical(id)
    |> downgrade(version)
  end