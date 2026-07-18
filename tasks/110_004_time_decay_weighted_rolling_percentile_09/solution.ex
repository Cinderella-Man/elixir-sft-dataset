  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    half_life = validate_positive(Keyword.fetch!(opts, :half_life_ms), :half_life_ms)
    max_samples = validate_optional_positive(Keyword.get(opts, :max_samples))

    {:ok,
     %{
       clock: clock,
       half_life: half_life,
       max_samples: max_samples,
       series: %{}
     }}
  end