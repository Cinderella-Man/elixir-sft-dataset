  @impl true
  def handle_call({:identifier, input}, _from, state) do
    case do_identifier(input) do
      {:ok, s} ->
        {:reply, {:ok, s}, inc(state, [:identifiers])}

      {:error, :empty} = err ->
        {:reply, err, inc(state, [:identifiers, :identifiers_blocked])}
    end
  end

  @impl true
  def handle_call({:filename, input}, _from, %{max_filename_length: max} = state) do
    case do_filename(input) do
      {:error, :empty} = err ->
        {:reply, err, inc(state, [:filenames, :filenames_blocked])}

      {:ok, name} ->
        {truncated?, final} =
          if String.length(name) > max do
            {true, String.slice(name, 0, max)}
          else
            {false, name}
          end

        keys = if truncated?, do: [:filenames, :filenames_truncated], else: [:filenames]
        {:reply, {:ok, final}, inc(state, keys)}
    end
  end

  @impl true
  def handle_call({:html, input}, _from, state) do
    {cleaned, count} = do_strip_html(input)

    metrics =
      state.metrics
      |> Map.update!(:html_calls, &(&1 + 1))
      |> Map.update!(:tags_stripped, &(&1 + count))

    {:reply, {:ok, cleaned, count}, %{state | metrics: metrics}}
  end

  @impl true
  def handle_call(:metrics, _from, state), do: {:reply, state.metrics, state}

  @impl true
  def handle_call(:reset_metrics, _from, state),
    do: {:reply, :ok, %{state | metrics: @default_metrics}}