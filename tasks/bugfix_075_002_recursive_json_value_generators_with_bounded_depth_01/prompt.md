# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# Specification: `JsonGenerators` — Recursive JSON Value Generators with Bounded Depth

## Overview

This document specifies an Elixir module named `JsonGenerators` that provides reusable `StreamData` generators for **recursive, JSON-shaped values**. The module is intended for use with property-based testing via the `StreamData` and `ExUnitProperties` libraries.

Unlike flat domain-model generators, the interesting constraint here is **bounded recursion depth**: nested arrays and objects must never nest deeper than a caller-specified limit, and that bound must be guaranteed structurally (never by rejection/filtering).

The depth of a value is defined as follows: a scalar (null, boolean, integer, string) has depth `0`; a container (array or object) has depth `1 + max(depth of its children)`, where an empty container has depth `1`.

## API

The public API consists of the following generators:

- `JsonGenerators.scalar()` — produces a JSON scalar: one of `nil`, a boolean, an integer, or an alphanumeric string (max 8 chars). Depth is always `0`.
- `JsonGenerators.array(element_gen, max_length)` — produces a list of `0..max_length` elements drawn from `element_gen`.
- `JsonGenerators.object(value_gen, max_length)` — produces a map with `0..max_length` entries, where each key is a **non-empty** alphanumeric string and each value is drawn from `value_gen`.
- `JsonGenerators.value(max_depth)` — produces an arbitrary JSON value (scalar, array, or object).

## Edge cases and constraints

- For `JsonGenerators.value(max_depth)`: when `max_depth <= 0` it always produces a scalar; otherwise it may produce scalars or containers whose children are drawn from `value(max_depth - 1)`. The generated value's depth must **always** be `<= max_depth`.
- All depth and shape constraints must be enforced inside the generators themselves — consumers should never need to call `StreamData.filter/2`.
- Each generator must return a `%StreamData{}` struct so it composes with the standard `StreamData` combinators.

## Deliverable

The complete module is to be delivered in a single file, using only `stream_data` as an external dependency, no others.

## The buggy module

```elixir
defmodule JsonGenerators do
  @moduledoc """
  Reusable `StreamData` generators for recursive, JSON-shaped values, intended
  for use with property-based testing via `StreamData` and `ExUnitProperties`.

  The distinguishing feature of these generators is **structurally-bounded
  recursion depth**: `value/1` never produces a value that nests deeper than the
  requested limit, and that guarantee comes from the shape of the generator
  itself — never from rejection-filtering.

  Depth convention:

    * a scalar (`nil`, boolean, integer, string) has depth `0`
    * a container (list/map) has depth `1 + max(child depths)`; an empty
      container has depth `1`

  ## Usage

      use ExUnitProperties

      property "bounded json never nests too deep" do
        check all value <- JsonGenerators.value(3) do
          assert depth(value) <= 3
        end
      end

  All generators return `%StreamData{}` structs and compose with the standard
  `StreamData` combinator API.
  """

  # Qualify every call explicitly rather than bulk-importing StreamData: a bare
  # `import StreamData` pulls in dozens of functions whose arities can clash with
  # auto-imported Kernel functions.
  alias StreamData, as: SD

  @doc """
  Produces a JSON scalar: one of `nil`, a boolean, an integer, or an
  alphanumeric string of at most 8 characters. Always depth `0`.
  """
  @spec scalar() :: StreamData.t(term())
  def scalar do
    SD.one_of([
      SD.constant(nil),
      SD.boolean(),
      SD.integer(),
      SD.string(:alphanumeric, max_length: 9)
    ])
  end

  @doc """
  Produces a list of `0..max_length` elements drawn from `element_gen`.
  """
  @spec array(StreamData.t(a), non_neg_integer()) :: StreamData.t([a]) when a: term()
  def array(element_gen, max_length) when is_integer(max_length) and max_length >= 0 do
    SD.list_of(element_gen, max_length: max_length)
  end

  @doc """
  Produces a map of `0..max_length` entries where every key is a non-empty
  alphanumeric string and every value is drawn from `value_gen`.

  Keys are drawn independently, so the final map may contain fewer than
  `max_length` entries when keys collide — this is always a valid object.
  """
  @spec object(StreamData.t(a), non_neg_integer()) :: StreamData.t(%{optional(String.t()) => a})
        when a: term()
  def object(value_gen, max_length) when is_integer(max_length) and max_length >= 0 do
    key = SD.string(:alphanumeric, min_length: 1, max_length: 8)
    pair = SD.tuple({key, value_gen})

    SD.map(SD.list_of(pair, max_length: max_length), &Map.new/1)
  end

  @doc """
  Produces an arbitrary JSON value whose depth is guaranteed `<= max_depth`.

  For `max_depth <= 0` this always yields a scalar. For a positive depth it may
  yield a scalar, or a container whose children are drawn from
  `value(max_depth - 1)` — so by induction the depth invariant always holds.
  """
  @spec value(integer()) :: StreamData.t(term())
  def value(max_depth) when is_integer(max_depth) and max_depth <= 0 do
    scalar()
  end

  def value(max_depth) when is_integer(max_depth) and max_depth > 0 do
    child = value(max_depth - 1)

    SD.one_of([
      scalar(),
      array(child, 5),
      object(child, 5)
    ])
  end
end
```

## Failing test report

```
2 of 21 test(s) failed:

  * property JsonGenerators.scalar/0 strings are alphanumeric and at most 8 chars
      
      
      Failed with generated values (after 58 successful runs):
      
               * Clause:    v <- JsonGenerators.scalar()
                 Generated: "Aa0AbswNK"
      
           Assertion with <= failed
      code:  assert String.length(v) <= 8
      left:  9
      right: 8
      

  * test scalar strings attain the documented 8-char maximum across seeded samples
      
      
      Assertion with == failed
      code:  assert Enum.max(lengths) == 8
      left:  9
      right: 8
```
