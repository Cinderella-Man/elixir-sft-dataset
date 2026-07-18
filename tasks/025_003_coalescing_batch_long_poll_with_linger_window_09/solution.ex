  @doc "Plug callback. Returns the options unchanged."
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts