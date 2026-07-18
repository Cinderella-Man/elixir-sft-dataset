  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    edges = validate_edges(Keyword.get(opts, :edges))
    window_ms = validate_positive(Keyword.fetch!(opts, :window_ms), :window_ms)
    slots = validate_positive(Keyword.get(opts, :slots, 60), :slots)
    slice_ms = max(1, div(window_ms + slots - 1, slots))

    {:ok,
     %{
       clock: clock,
       edges: edges,
       edges_t: List.to_tuple(edges),
       bucket_count: length(edges) - 1,
       window_ms: window_ms,
       slots: slots,
       slice_ms: slice_ms,
       series: %{}
     }}
  end