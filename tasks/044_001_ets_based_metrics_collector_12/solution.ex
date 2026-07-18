  @doc """
  Returns a point-in-time snapshot of all metrics as `%{name => value}`.

  Semantically identical to `all/0` but signals to the reader that the
  returned map is an immutable capture — subsequent mutations do not
  affect it.
  """
  @spec snapshot() :: %{term() => number()}
  def snapshot, do: all()