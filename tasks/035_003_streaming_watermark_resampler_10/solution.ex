  @impl true
  def init({interval_ms, opts}) do
    state = %{
      interval: interval_ms,
      lateness: Keyword.get(opts, :allowed_lateness, 0),
      agg: fetch_opt!(opts, :agg, :last, @valid_agg),
      fill: fetch_opt!(opts, :fill, nil, @valid_fill),
      open: %{},
      emitted: [],
      next_emit: nil,
      last_value: nil,
      late_dropped: 0,
      watermark: nil
    }

    {:ok, state}
  end