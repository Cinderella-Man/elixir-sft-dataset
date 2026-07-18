  @impl true
  def init({secret, clock}) do
    {:ok, %State{secret: secret, clock: clock, consumed: MapSet.new()}}
  end