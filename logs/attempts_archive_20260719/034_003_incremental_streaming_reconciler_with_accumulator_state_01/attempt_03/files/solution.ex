defmodule Reconciler do
  @moduledoc """
  Incremental reconciliation of two sides of records by a shared composite key.

  Instead of taking both full lists at once, `Reconciler` builds a
  reconciliation one record at a time through a pure functional accumulator.
  This suits streaming pipelines where left-side and right-side records arrive
  interleaved.

  The state produced by `new/1` is an opaque, immutable value. Records are
  folded in via `put_left/2` and `put_right/2` (last write wins per side per
  key), and the final reconciliation is produced by `result/1`.

  ## Example

      state =
        Reconciler.new(key_fields: [:id])
        |> Reconciler.put_left(%{id: 1, name: "a"})
        |> Reconciler.put_right(%{id: 1, name: "b"})

      Reconciler.result(state)
      # => %{
      #      matched: [
      #        %{
      #          left: %{id: 1, name: "a"},
      #          right: %{id: 1, name: "b"},
      #          differences: %{name: %{left: "a", right: "b"}}
      #        }
      #      ],
      #      only_in_left: [],
      #      only_in_right: []
      #    }

  """

  @typedoc "A record folded into the reconciler."
  @type record :: map()

  @typedoc "Opaque reconciler state; do not depend on its internal shape."
  @opaque t :: %__MODULE__{
            key_fields: [atom()],
            compare_fields: [atom()] | nil,
            left: %{optional(term()) => record()},
            right: %{optional(term()) => record()}
          }

  @typedoc "Per-field difference map for matched records."
  @type diff_map :: %{optional(term()) => %{left: term(), right: term()}}

  @typedoc "The reconciliation result returned by `result/1`."
  @type result :: %{
          matched: [%{left: record(), right: record(), differences: diff_map()}],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  @enforce_keys [:key_fields, :compare_fields, :left, :right]
  defstruct [:key_fields, :compare_fields, :left, :right]

  @doc """
  Creates a new, empty reconciler state.

  `opts` is a keyword list:

    * `:key_fields` (required) — a list of atoms forming the composite match
      key, e.g. `[:id]` or `[:org_id, :user_id]`.
    * `:compare_fields` (optional) — a list of atoms specifying which fields to
      diff on matched records. If omitted or `nil`, all fields except the key
      fields are compared.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    key_fields = Keyword.fetch!(opts, :key_fields)
    compare_fields = Keyword.get(opts, :compare_fields)

    validate_key_fields!(key_fields)
    validate_compare_fields!(compare_fields)

    %__MODULE__{
      key_fields: key_fields,
      compare_fields: compare_fields,
      left: %{},
      right: %{}
    }
  end

  @doc """
  Folds `record` into the left side of the reconciliation.

  Returns a new state. If a left record with the same composite key was already
  added, it is replaced (last write wins).
  """
  @spec put_left(t(), record()) :: t()
  def put_left(%__MODULE__{} = state, record) when is_map(record) do
    key = extract_key(record, state.key_fields)
    %__MODULE__{state | left: Map.put(state.left, key, record)}
  end

  @doc """
  Folds `record` into the right side of the reconciliation.

  Returns a new state. If a right record with the same composite key was already
  added, it is replaced (last write wins).
  """
  @spec put_right(t(), record()) :: t()
  def put_right(%__MODULE__{} = state, record) when is_map(record) do
    key = extract_key(record, state.key_fields)
    %__MODULE__{state | right: Map.put(state.right, key, record)}
  end

  @doc """
  Produces the reconciliation from the current state.

  Returns a map with `:matched`, `:only_in_left`, and `:only_in_right`. The
  order of records within each list is unspecified.
  """
  @spec result(t()) :: result()
  def result(%__MODULE__{left: left, right: right} = state) do
    matched =
      for {key, left_record} <- left, Map.has_key?(right, key) do
        right_record = Map.fetch!(right, key)

        %{
          left: left_record,
          right: right_record,
          differences: diff(left_record, right_record, state)
        }
      end

    only_in_left =
      for {key, record} <- left, not Map.has_key?(right, key), do: record

    only_in_right =
      for {key, record} <- right, not Map.has_key?(left, key), do: record

    %{
      matched: matched,
      only_in_left: only_in_left,
      only_in_right: only_in_right
    }
  end

  # Validates that :key_fields is a list of atoms, raising otherwise.
  defp validate_key_fields!(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      :ok
    else
      raise ArgumentError, ":key_fields must be a list of atoms"
    end
  end

  defp validate_key_fields!(_fields) do
    raise ArgumentError, ":key_fields must be a list of atoms"
  end

  # Validates that :compare_fields is nil or a list of atoms, raising otherwise.
  defp validate_compare_fields!(nil), do: :ok

  defp validate_compare_fields!(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      :ok
    else
      raise ArgumentError, ":compare_fields must be nil or a list of atoms"
    end
  end

  defp validate_compare_fields!(_fields) do
    raise ArgumentError, ":compare_fields must be nil or a list of atoms"
  end

  # Builds the composite match key (a list of key-field values) for a record.
  defp extract_key(record, key_fields) do
    Enum.map(key_fields, fn field -> Map.get(record, field) end)
  end

  # Computes the per-field difference map for a matched left/right pair.
  defp diff(left_record, right_record, state) do
    fields = fields_to_compare(left_record, right_record, state)

    Enum.reduce(fields, %{}, fn field, acc ->
      left_value = Map.get(left_record, field)
      right_value = Map.get(right_record, field)

      if left_value == right_value do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value})
      end
    end)
  end

  # Resolves which fields participate in the diff for a matched pair.
  defp fields_to_compare(_left_record, _right_record, %__MODULE__{compare_fields: fields})
       when is_list(fields) do
    fields
  end

  defp fields_to_compare(left_record, right_record, %__MODULE__{
         compare_fields: nil,
         key_fields: key_fields
       }) do
    key_set = MapSet.new(key_fields)

    left_record
    |> Map.keys()
    |> Enum.concat(Map.keys(right_record))
    |> Enum.uniq()
    |> Enum.reject(fn field -> MapSet.member?(key_set, field) end)
  end
end
