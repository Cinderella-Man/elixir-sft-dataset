  @doc """
  Returns the flag's declared prerequisite list, or `[]` for unknown flags.
  """
  @spec prerequisites(atom()) :: [atom()]
  def prerequisites(flag) do
    case record(flag) do
      nil -> []
      {_state, prereqs} -> prereqs
    end
  end