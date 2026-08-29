# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FieldFormatterAtomSafetyTest do
  @moduledoc """
  Regression coverage for CVE-3192: client-supplied field names must never mint
  new atoms via `resolve_field_name/2`, which would allow atom-table
  exhaustion (a node-wide denial of service).

  The property is checked by confirming no atom exists for an unknown name after
  the call (via `String.to_existing_atom/1` raising) rather than by sampling the
  global atom count, which concurrent test modules would perturb.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.FieldFormatter

  defp atom_exists?(name) when is_binary(name) do
    _ = String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end

  test "resolves an existing field name to its atom" do
    # :user_name exists as an atom because a resource attribute is named that.
    _ = :user_name
    assert FieldFormatter.resolve_field_name("userName", :camel_case) == :user_name
  end

  test "passes atoms through unchanged" do
    assert FieldFormatter.resolve_field_name(:already_atom, :camel_case) == :already_atom
  end

  test "never mints a new atom for an unknown field name" do
    unique = "atom_bomb_field_name_#{System.unique_integer([:positive])}_xyz"
    camel = "atomBombFieldName#{System.unique_integer([:positive])}Xyz"

    refute atom_exists?(unique)

    result = FieldFormatter.resolve_field_name(camel, :camel_case)

    # Falls back to the (formatted) string, which downstream field selection
    # rejects as an unknown field rather than atomizing.
    assert is_binary(result)
    # No atom was created for the resolved/formatted name.
    refute atom_exists?(result)
  end

  test "does not mint atoms for a batch of unique field names" do
    names = for i <- 1..1_000, do: "atomBombBatch#{i}_#{System.unique_integer([:positive])}"

    Enum.each(names, fn name ->
      result = FieldFormatter.resolve_field_name(name, :camel_case)
      assert is_binary(result)
      refute atom_exists?(result)
    end)
  end

  test "does not raise on field names longer than the 255-char atom limit" do
    long = String.duplicate("a", 300)

    result = FieldFormatter.resolve_field_name(long, :camel_case)
    assert is_binary(result)
  end
end
