  @doc """
  Start the streaming resampler.

  `interval_ms` is the bucket width in milliseconds and must be a positive
  integer. Options:

    * `:agg` — aggregation mode, one of `#{inspect(@valid_agg)}` (default `:last`)
    * `:fill` — gap-fill policy, one of `#{inspect(@valid_fill)}` (default `:nil`)
    * `:allowed_lateness` — non-negative integer milliseconds (default `0`)

  Raises `ArgumentError` for an invalid `interval_ms` or invalid options.
  """
  @spec start_link(pos_integer(), keyword()) :: GenServer.on_start()
  def start_link(interval_ms, opts \\ []) do
    unless is_integer(interval_ms) and interval_ms > 0 do
      raise ArgumentError, "interval_ms must be a positive integer, got: #{inspect(interval_ms)}"
    end

    _ = fetch_opt!(opts, :agg, :last, @valid_agg)
    _ = fetch_opt!(opts, :fill, nil, @valid_fill)

    lateness = Keyword.get(opts, :allowed_lateness, 0)

    unless is_integer(lateness) and lateness >= 0 do
      raise ArgumentError,
            "allowed_lateness must be a non-negative integer, got: #{inspect(lateness)}"
    end

    GenServer.start_link(__MODULE__, {interval_ms, opts})
  end