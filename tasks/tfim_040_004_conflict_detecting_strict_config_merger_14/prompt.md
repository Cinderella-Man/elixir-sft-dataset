# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule StrictConfigMerger do
  @moduledoc """
  Deep-merges two configuration maps while detecting conflicts.

  Returns `{:ok, merged}` when no conflicts are found, otherwise `{:error, conflicts}`
  with the conflicts sorted by key-path. Conflict kinds:

    * `:type_mismatch` (only when `:strict` is `true`) — both sides hold values of
      differing kinds at the same path.
    * `:locked_violation` — an override changes a `:locked` path's value.
    * `:missing_required` — a `:required` path is absent from the merged result.
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Deep-merges `override_config` onto `base_config`, detecting conflicts.

  Supported `opts`:

    * `:strict` (boolean, default `false`) — flag differing value kinds at the same
      path as `:type_mismatch` conflicts.
    * `:list_strategy` (`:replace` | `:append`, default `:replace`) — how lists at the
      same path combine.
    * `:list_strategies` — a map of key-path (list/tuple of atoms) to a per-path list
      strategy overriding the global one.
    * `:locked` — a list of key-paths that must keep their base value.
    * `:required` — a list of key-paths that must be present in the merged result.

  Returns `{:ok, merged_map}` when there are no conflicts, or `{:error, conflicts}`
  where `conflicts` is a list of conflict maps sorted by their key-path.
  """
  @spec merge(map(), map(), keyword()) :: {:ok, map()} | {:error, [map()]}
  def merge(base_config, override_config, opts \\ [])
      when is_map(base_config) and is_map(override_config) do
    resolved = resolve_opts(opts)

    {merged, conflicts} = do_merge(base_config, override_config, [], resolved)

    missing =
      for path <- resolved.required, not path_present?(merged, path) do
        %{type: :missing_required, path: path}
      end

    all = conflicts ++ missing

    case all do
      [] -> {:ok, merged}
      _ -> {:error, Enum.sort_by(all, & &1.path)}
    end
  end

  # ---------------------------------------------------------------------------
  # Recursive merge collecting conflicts
  # ---------------------------------------------------------------------------

  defp do_merge(base, over, path, opts) when is_map(base) and is_map(over) do
    keys = Enum.uniq(Map.keys(base) ++ Map.keys(over))

    Enum.reduce(keys, {%{}, []}, fn k, {acc, conf} ->
      kpath = path ++ [k]

      cond do
        not Map.has_key?(over, k) ->
          {Map.put(acc, k, Map.fetch!(base, k)), conf}

        not Map.has_key?(base, k) ->
          {Map.put(acc, k, Map.fetch!(over, k)), conf}

        true ->
          {value, new_conf} =
            merge_value(Map.fetch!(base, k), Map.fetch!(over, k), kpath, opts)

          {Map.put(acc, k, value), conf ++ new_conf}
      end
    end)
  end

  defp merge_value(bv, ov, kpath, opts) do
    cond do
      locked?(kpath, opts) and bv != ov ->
        {bv, [%{type: :locked_violation, path: kpath, base: bv, override: ov}]}

      locked?(kpath, opts) ->
        {bv, []}

      is_map(bv) and is_map(ov) ->
        do_merge(bv, ov, kpath, opts)

      is_list(bv) and is_list(ov) ->
        case list_strategy_for(kpath, opts) do
          :replace -> {ov, []}
          :append -> {bv ++ ov, []}
        end

      opts.strict and type_kind(bv) != type_kind(ov) ->
        {ov, [%{type: :type_mismatch, path: kpath, base: bv, override: ov}]}

      true ->
        {ov, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Options + helpers
  # ---------------------------------------------------------------------------

  defp resolve_opts(opts) do
    per_key =
      opts
      |> Keyword.get(:list_strategies, %{})
      |> Map.new(fn {path, strat} -> {normalise_path(path), strat} end)

    %{
      strict: Keyword.get(opts, :strict, false),
      global_list_strategy: Keyword.get(opts, :list_strategy, :replace),
      per_key_strategies: per_key,
      locked_paths: Enum.map(Keyword.get(opts, :locked, []), &normalise_path/1),
      required: Enum.map(Keyword.get(opts, :required, []), &normalise_path/1)
    }
  end

  defp normalise_path(path) when is_list(path), do: path
  defp normalise_path(path) when is_tuple(path), do: Tuple.to_list(path)

  defp locked?(kpath, %{locked_paths: locked}), do: kpath in locked

  defp list_strategy_for(kpath, %{per_key_strategies: per_key, global_list_strategy: global}) do
    Map.get(per_key, kpath, global)
  end

  defp path_present?(_map, []), do: true

  defp path_present?(map, [k | rest]) when is_map(map) do
    case Map.fetch(map, k) do
      {:ok, v} -> path_present?(v, rest)
      :error -> false
    end
  end

  defp path_present?(_map, _path), do: false

  defp type_kind(v) when is_integer(v), do: :integer
  defp type_kind(v) when is_float(v), do: :float
  defp type_kind(v) when is_boolean(v), do: :boolean
  defp type_kind(v) when is_atom(v), do: :atom
  defp type_kind(v) when is_binary(v), do: :binary
  defp type_kind(v) when is_list(v), do: :list
  defp type_kind(v) when is_map(v), do: :map
  defp type_kind(_v), do: :other
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule StrictConfigMergerTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "non-strict merge lets override win and returns :ok" do
    base = %{host: "localhost", port: 4000}
    override = %{port: 9000}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override)
    assert merged == %{host: "localhost", port: 9000}
  end

  test "deep merge returns :ok" do
    base = %{db: %{host: "localhost", port: 5432, name: "prod"}}
    override = %{db: %{port: 5433}}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override)
    assert merged.db == %{host: "localhost", port: 5433, name: "prod"}
  end

  test "strict merge with matching types returns :ok" do
    base = %{port: 4000, name: "a"}
    override = %{port: 9000, name: "b"}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: true)
    assert merged == %{port: 9000, name: "b"}
  end

  # -------------------------------------------------------
  # Type mismatch (strict)
  # -------------------------------------------------------

  test "strict scalar type mismatch is a conflict" do
    base = %{port: 5432}
    override = %{port: "5433"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, strict: true)
    assert conflict.type == :type_mismatch
    assert conflict.path == [:port]
    assert conflict.base == 5432
    assert conflict.override == "5433"
  end

  test "strict structural mismatch (map vs scalar) is a conflict" do
    base = %{db: %{host: "localhost"}}
    override = %{db: "disabled"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, strict: true)
    assert conflict.type == :type_mismatch
    assert conflict.path == [:db]
  end

  test "non-strict type mismatch is NOT a conflict; override wins" do
    base = %{port: 5432}
    override = %{port: "5433"}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: false)
    assert merged.port == "5433"
  end

  test "two lists never count as a type mismatch even in strict mode" do
    base = %{tags: ["a"]}
    override = %{tags: ["b"]}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: true)
    assert merged.tags == ["b"]
  end

  # -------------------------------------------------------
  # Locked
  # -------------------------------------------------------

  test "locked violation is a conflict regardless of strict" do
    base = %{secret: "keep"}
    override = %{secret: "change"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, locked: [[:secret]])
    assert conflict.type == :locked_violation
    assert conflict.path == [:secret]
    assert conflict.base == "keep"
    assert conflict.override == "change"
  end

  test "locked path with identical override value is fine" do
    base = %{secret: "keep", other: 1}
    override = %{secret: "keep", other: 2}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, locked: [[:secret]])
    assert merged.secret == "keep"
    assert merged.other == 2
  end

  test "nested locked violation is detected" do
    base = %{db: %{password: "s3cr3t"}}
    override = %{db: %{password: "pwned"}}

    assert {:error, [conflict]} =
             StrictConfigMerger.merge(base, override, locked: [[:db, :password]])

    assert conflict.type == :locked_violation
    assert conflict.path == [:db, :password]
  end

  # -------------------------------------------------------
  # Required
  # -------------------------------------------------------

  test "missing required key is a conflict" do
    base = %{a: 1}
    override = %{}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, required: [[:b]])
    assert conflict.type == :missing_required
    assert conflict.path == [:b]
  end

  test "present required key passes" do
    base = %{a: %{b: 1}}
    override = %{}

    assert {:ok, _merged} = StrictConfigMerger.merge(base, override, required: [[:a, :b]])
  end

  # -------------------------------------------------------
  # List strategy
  # -------------------------------------------------------

  test "append list strategy concatenates and returns :ok" do
    # TODO
  end

  # -------------------------------------------------------
  # Multiple conflicts sorted by path
  # -------------------------------------------------------

  test "multiple conflicts are returned sorted by path" do
    base = %{a: 1, z: 2}
    override = %{a: "x", z: [1]}

    assert {:error, conflicts} = StrictConfigMerger.merge(base, override, strict: true)
    assert Enum.map(conflicts, & &1.path) == [[:a], [:z]]
    assert Enum.all?(conflicts, &(&1.type == :type_mismatch))
  end

  test "conflicts across mismatch, lock, and required are all reported" do
    base = %{port: 1, secret: "keep"}
    override = %{port: "two", secret: "change"}

    assert {:error, conflicts} =
             StrictConfigMerger.merge(base, override,
               strict: true,
               locked: [[:secret]],
               required: [[:missing]]
             )

    types = conflicts |> Enum.map(& &1.type) |> Enum.sort()
    assert types == [:locked_violation, :missing_required, :type_mismatch]
  end
end
```
