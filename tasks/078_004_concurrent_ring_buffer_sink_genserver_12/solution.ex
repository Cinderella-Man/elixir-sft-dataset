  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    {:ok, fresh_state(capacity)}
  end