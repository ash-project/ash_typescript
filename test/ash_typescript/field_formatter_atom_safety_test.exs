# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FieldFormatterAtomSafetyTest do
  @moduledoc """
  Regression coverage for CVE-3192: client-supplied field names must never mint
  new atoms, which would allow atom-table exhaustion (a node-wide denial of
  service). Client names are resolved by exact lookup in the manifest's reverse
  maps, so an unknown name stays a string and is rejected as an unknown field.

  The property is checked by confirming no atom exists for an unknown name after
  the call (via `String.to_existing_atom/1` raising) rather than by sampling the
  global atom count, which concurrent test modules would perturb.
  """
  use ExUnit.Case, async: true
  import AshTypescript.Test.TestHelpers, only: [rpc_runtime: 0]

  defp atom_exists?(name) when is_binary(name) do
    _ = String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end

  defp select_todo_fields(fields),
    do:
      AshRpc.RequestedFieldsProcessor.process(
        rpc_runtime(),
        AshTypescript.Test.Todo,
        :read,
        fields
      )

  describe "resource field selection (CVE-3192)" do
    test "resolves an existing client name to its atom" do
      assert {:ok, {select, _load, _template}} = select_todo_fields(["dueDate"])
      assert :due_date in select
    end

    test "never mints a new atom for an unknown field name" do
      camel = "atomBombFieldName#{System.unique_integer([:positive])}Xyz"

      refute atom_exists?(camel)
      refute atom_exists?(Macro.underscore(camel))

      # Rejected as an unknown field, named as the client sent it
      assert {:error, {:unknown_field, ^camel, AshTypescript.Test.Todo, []}} =
               select_todo_fields([camel])

      refute atom_exists?(camel)
      refute atom_exists?(Macro.underscore(camel))
    end

    test "does not mint atoms for a batch of unique field names" do
      names = for i <- 1..1_000, do: "atomBombBatch#{i}_#{System.unique_integer([:positive])}"

      Enum.each(names, fn name ->
        assert {:error, {:unknown_field, ^name, _, _}} = select_todo_fields([name])
        refute atom_exists?(name)
        refute atom_exists?(Macro.underscore(name))
      end)
    end

    test "does not raise on field names longer than the 255-char atom limit" do
      long = String.duplicate("a", 300)

      assert {:error, {:unknown_field, ^long, _, _}} = select_todo_fields([long])
    end
  end

  describe "typed struct field selection (CVE-3209)" do
    # AshTypescript.Test.Todo's :statistics attribute is a TypedStruct that
    # implements typescript_field_names/0, so field selection on it routes through
    # FieldSelector.select_typed_struct_fields/4 - a distinct call site from the
    # one CVE-3192 covered, which minted an atom per unknown name.
    defp select_statistics_fields(fields) do
      AshRpc.RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
        %{"statistics" => fields}
      ])
    end

    test "an unknown field name is rejected without minting an atom" do
      name = "zzAtomBombStat#{System.unique_integer([:positive])}"

      refute atom_exists?(Macro.underscore(name))

      assert {:error, {:unknown_field, unknown, "field_constrained_type", [:statistics]}} =
               select_statistics_fields([name])

      assert is_binary(unknown)
      refute atom_exists?(unknown)
    end

    test "a batch of unique unknown field names mints no atoms" do
      names = for i <- 1..500, do: "zzAtomBombBatch#{i}_#{System.unique_integer([:positive])}"

      Enum.each(names, fn name ->
        assert {:error, {:unknown_field, _, _, _}} = select_statistics_fields([name])
        refute atom_exists?(Macro.underscore(name))
      end)
    end

    test "valid field names still resolve, including mapped ones" do
      assert {:ok, {_select, _load, template}} =
               select_statistics_fields(["viewCount", "allCompleted"])

      assert [statistics: [:view_count, :all_completed?]] = template
    end
  end
end
