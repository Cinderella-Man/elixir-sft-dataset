  @doc """
  Merges `layers` (a non-empty list of `{name, config_map}` tuples in increasing
  precedence order) into a single effective configuration.

  Returns a map with two keys: `:config`, the deep-merged configuration, and
  `:provenance`, a map from each leaf key-path (a list of atoms) to the layer name
  that supplied the winning value. For appended lists the provenance is the ordered
  list of contributing layer names.

  Supported `opts`:

    * `:list_strategy` — `:replace` (default) or `:append` for list leaves.
    * `:list_strategies` — a map of `key_path => :replace | :append` overriding the
      global strategy for specific paths.
    * `:locked` — a list of key-paths that, once set by a lower layer, cannot be
      changed by higher layers.

  Key paths for `:list_strategies` and `:locked` are lists or tuples of atoms.
  Raises `ArgumentError` when `layers` is empty.
  """
  @spec merge([{term(), map()}], keyword()) :: %{config: map(), provenance: map()}
  def merge(layers, opts \\ []) when is_list(layers) do
    if layers == [] do
      raise ArgumentError, "`layers` must be a non-empty list of {name, map} tuples"
    end

    resolved = resolve_opts(opts)

    [{first_name, first_map} | rest] = Enum.map(layers, &normalise_layer/1)
    init_prov = leaf_provenance(first_map, first_name, [], %{})

    {config, provenance} =
      Enum.reduce(rest, {first_map, init_prov}, fn {name, map}, {acc_map, acc_prov} ->
        merge_map(acc_map, map, name, [], acc_prov, resolved)
      end)

    %{config: config, provenance: provenance}
  end