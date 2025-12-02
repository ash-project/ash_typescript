# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.Introspection do
  @moduledoc """
  Core type introspection and classification for Ash types.

  This module delegates to `AshIntrospection.TypeSystem.Introspection` for the core
  functionality and provides TypeScript-specific extensions.
  """

  # Delegate all core functions to AshIntrospection
  defdelegate is_embedded_resource?(module), to: AshIntrospection.TypeSystem.Introspection
  defdelegate is_primitive_type?(type), to: AshIntrospection.TypeSystem.Introspection
  defdelegate classify_ash_type(type_module, attribute, is_array), to: AshIntrospection.TypeSystem.Introspection
  defdelegate get_union_types(attribute), to: AshIntrospection.TypeSystem.Introspection
  defdelegate get_union_types_from_constraints(type, constraints), to: AshIntrospection.TypeSystem.Introspection
  defdelegate get_inner_type(type), to: AshIntrospection.TypeSystem.Introspection
  defdelegate is_ash_type?(module), to: AshIntrospection.TypeSystem.Introspection

  @doc """
  Recursively unwraps Ash.Type.NewType to get the underlying type and constraints.

  Uses :typescript_field_names as the callback to check for field name mappings.
  """
  def unwrap_new_type(type, constraints) do
    AshIntrospection.TypeSystem.Introspection.unwrap_new_type(type, constraints, :typescript_field_names)
  end
end
