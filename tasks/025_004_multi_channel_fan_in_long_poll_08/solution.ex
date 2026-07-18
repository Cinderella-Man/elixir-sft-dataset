  @doc "Plug callback; returns the options unchanged."
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts