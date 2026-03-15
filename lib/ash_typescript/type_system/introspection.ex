# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.Introspection do
  @moduledoc """
  Raw Ash type introspection helpers for compile-time verifiers.

  These functions operate on raw Ash types (atoms, not `%AshApiSpec.Type{}`)
  and are used by verifiers that run before the AshApiSpec is generated.

  For runtime/codegen use, prefer `AshApiSpec.Generator.TypeResolver` and
  `AshTypescript.Rpc.TypeIndex` which work with pre-resolved spec types.
  """

  @doc """
  Recursively unwraps Ash.Type.NewType to get the underlying type and constraints.

  Adds `instance_of` to constraints when the NewType has `typescript_field_names/0`.
  """
  def unwrap_new_type(type, constraints) when is_atom(type) do
    if Ash.Type.NewType.new_type?(type) do
      subtype = Ash.Type.NewType.subtype_of(type)

      constraints =
        case type.do_init(constraints) do
          {:ok, merged_constraints} -> merged_constraints
          {:error, _} -> constraints
        end

      augmented_constraints =
        if function_exported?(type, :typescript_field_names, 0) and
             not Keyword.has_key?(constraints, :instance_of) do
          Keyword.put(constraints, :instance_of, type)
        else
          constraints
        end

      {subtype, augmented_constraints}
    else
      {type, constraints}
    end
  end

  def unwrap_new_type(type, constraints), do: {type, constraints}
end
