  @doc """
  Stores the interval `{start, finish}` and returns `{:ok, id}`.

  `id` is a unique integer handle for the stored interval. Identical intervals
  may be inserted repeatedly and each receives its own id.

  Ids are handed out by the server in insertion order: the first successful
  insert returns `1`, and every later insert returns the previous id plus one.
  Ids are never reused, even after the interval they name is removed.
  """
  @spec insert(GenServer.server(), interval()) :: {:ok, pos_integer()}
  def insert(server, {s, f}) when is_integer(s) and is_integer(f) and s <= f do
    GenServer.call(server, {:insert, s, f})
  end