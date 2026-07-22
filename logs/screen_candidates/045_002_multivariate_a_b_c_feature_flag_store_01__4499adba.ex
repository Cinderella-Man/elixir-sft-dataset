defmodule FeatureFlags do
  @moduledoc """
  Multivariate feature flags backed by ETS for reads and a `GenServer` for writes.

  A flag can be in one of three states:

    * `:on`  — globally enabled for everybody;
    * `:off` — globally disabled (this is also the state of unknown flags);
    * multivariate — a weighted split across named variants, where each user is
      deterministically assigned to exactly one variant.

  Reads (`enabled?/1`, `variant_for/2`, `enabled_for?/2`) hit the named ETS table
  directly from the calling process, so they never block on the `GenServer`. All
  writes (`enable/1`, `disable/1`, `set_variants/2`) are serialised through the
  `GenServer`, which owns the table.

  ## Variant assignment

  Assignment is deterministic: the bucket for a user is
  `:erlang.phash2({flag_name, user_id}, 100)`, a value in `0..99`. Variants are
  walked in the order they were given, accumulating weights, and the variant whose
  cumulative range contains the bucket wins. With `[a: 50, b: 30, c: 20]` variant
  `:a` owns buckets `0..49`, `:b` owns `50..79` and `:c` owns `80..99`. Weights must
  sum to exactly `100`; a variant with weight `0` never receives any user.

  ## Example

      {:ok, _pid} = FeatureFlags.start_link([])
      :ok = FeatureFlags.set_variants(:checkout, a: 50, b: 30, c: 20)
      FeatureFlags.variant_for(:checkout, "user-42")
      #=> :a (stable for that user)

  """

  use GenServer

  @default_table :feature_flags
  @buckets 100

  @typedoc "The name of a feature flag."
  @type flag_name :: atom()

  @typedoc "The name of a variant within a multivariate flag."
  @type variant_name :: atom()

  @typedoc "A `{variant_name, weight}` pair; weights across a flag must sum to 100."
  @type variant :: {variant_name(), non_neg_integer()}

  @typedoc "The stored state of a flag."
  @type flag_state :: :on | :off | {:variants, [variant()]}

  # ── Public API ────────────────────────────────────────────────────────────────

  @doc """
  Starts the feature flag server and creates the backing ETS table.

  ## Options

    * `:table_name` — the name of the ETS table to create (default `#{inspect(@default_table)}`);
    * `:name` — the name to register the process under (default `FeatureFlags`);
      pass `nil` to skip registration.

  Any other options are ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table = Keyword.get(opts, :table_name, @default_table)
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    server_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, Keyword.put(opts, :table_name, table), server_opts)
  end

  @doc """
  Turns `flag_name` globally on.

  After this call `enabled?/1` returns `true` and `variant_for/2` returns `:on` for
  every user.
  """
  @spec enable(flag_name()) :: :ok
  def enable(flag_name) when is_atom(flag_name) do
    GenServer.call(__MODULE__, {:put, flag_name, :on})
  end

  @doc """
  Turns `flag_name` globally off.

  After this call `enabled?/1` and `enabled_for?/2` return `false` and `variant_for/2`
  returns `:off` for every user.
  """
  @spec disable(flag_name()) :: :ok
  def disable(flag_name) when is_atom(flag_name) do
    GenServer.call(__MODULE__, {:put, flag_name, :off})
  end

  @doc """
  Puts `flag_name` into multivariate mode with the given weighted `variants`.

  `variants` is a list of `{variant_name, weight}` tuples where `variant_name` is an
  atom and `weight` is a non-negative integer. The weights must sum to exactly `100`,
  otherwise an `ArgumentError` is raised. Variants are matched to buckets in the order
  given, so ordering is significant for assignment stability.

  ## Examples

      :ok = FeatureFlags.set_variants(:checkout, a: 50, b: 30, c: 20)

  """
  @spec set_variants(flag_name(), [variant()]) :: :ok
  def set_variants(flag_name, variants) when is_atom(flag_name) and is_list(variants) do
    validate_variants!(flag_name, variants)
    GenServer.call(__MODULE__, {:put, flag_name, {:variants, variants}})
  end

  @doc """
  Returns `true` only when `flag_name` is globally `:on`.

  Multivariate flags, `:off` flags and unknown flags all return `false`. Reads the ETS
  table directly and does not go through the server.
  """
  @spec enabled?(flag_name()) :: boolean()
  def enabled?(flag_name) when is_atom(flag_name) do
    lookup(flag_name) == :on
  end

  @doc """
  Returns the variant `user_id` is assigned to for `flag_name`.

    * `:on` flags return `:on` for every user;
    * `:off` flags and unknown flags return `:off`;
    * multivariate flags return the assigned variant atom.

  Assignment is deterministic: the same `{flag_name, user_id}` pair always yields the
  same variant, for as long as the flag's variant list is unchanged.

  ## Examples

      :ok = FeatureFlags.set_variants(:checkout, a: 100, b: 0)
      FeatureFlags.variant_for(:checkout, "user-1")
      #=> :a

  """
  @spec variant_for(flag_name(), term()) :: :on | :off | variant_name()
  def variant_for(flag_name, user_id) when is_atom(flag_name) do
    case lookup(flag_name) do
      :on -> :on
      {:variants, variants} -> pick_variant(variants, :erlang.phash2({flag_name, user_id}, @buckets))
      _other -> :off
    end
  end

  @doc """
  Returns `true` when `user_id` resolves to anything other than `:off` for `flag_name`.

  That is, `true` for globally-on flags and for any user assigned to a variant.
  """
  @spec enabled_for?(flag_name(), term()) :: boolean()
  def enabled_for?(flag_name, user_id) when is_atom(flag_name) do
    variant_for(flag_name, user_id) != :off
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    table = Keyword.get(opts, :table_name, @default_table)

    ^table =
      :ets.new(table, [
        :set,
        :named_table,
        :protected,
        read_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call({:put, flag_name, state}, _from, %{table: table} = server_state) do
    true = :ets.insert(table, {flag_name, state})
    {:reply, :ok, server_state}
  end

  # ── Internals ─────────────────────────────────────────────────────────────────

  @spec lookup(flag_name()) :: flag_state()
  defp lookup(flag_name) do
    case :ets.lookup(@default_table, flag_name) do
      [{^flag_name, state}] -> state
      [] -> :off
    end
  rescue
    ArgumentError -> :off
  end

  @spec pick_variant([variant()], non_neg_integer()) :: :off | variant_name()
  defp pick_variant(variants, bucket) do
    Enum.reduce_while(variants, 0, fn {name, weight}, acc ->
      upper = acc + weight

      if bucket < upper do
        {:halt, name}
      else
        {:cont, upper}
      end
    end)
    |> case do
      acc when is_integer(acc) -> :off
      name -> name
    end
  end

  @spec validate_variants!(flag_name(), [variant()]) :: :ok
  defp validate_variants!(flag_name, variants) do
    Enum.each(variants, fn
      {name, weight} when is_atom(name) and is_integer(weight) and weight >= 0 ->
        :ok

      other ->
        raise ArgumentError,
              "invalid variant #{inspect(other)} for flag #{inspect(flag_name)}: " <>
                "expected a {atom, non_neg_integer} tuple"
    end)

    total = Enum.reduce(variants, 0, fn {_name, weight}, acc -> acc + weight end)

    if total != 100 do
      raise ArgumentError,
            "variant weights for flag #{inspect(flag_name)} must sum to exactly 100, " <>
              "got #{total} from #{inspect(variants)}"
    end

    :ok
  end
end