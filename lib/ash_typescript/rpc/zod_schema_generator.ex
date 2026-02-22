# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ZodSchemaGenerator do
  @moduledoc """
  Deprecated: Use `AshTypescript.Codegen.ZodSchemaGenerator` instead.

  This module delegates to `AshTypescript.Codegen.ZodSchemaGenerator` for backward compatibility.
  """

  defdelegate map_zod_type(type, constraints \\ []), to: AshTypescript.Codegen.ZodSchemaGenerator

  defdelegate get_zod_type(type_and_constraints, context \\ nil),
    to: AshTypescript.Codegen.ZodSchemaGenerator

  defdelegate generate_zod_schema(resource, action, rpc_action_name),
    to: AshTypescript.Codegen.ZodSchemaGenerator

  defdelegate generate_zod_schemas_for_resources(resources),
    to: AshTypescript.Codegen.ZodSchemaGenerator

  defdelegate generate_zod_schema_for_resource(resource),
    to: AshTypescript.Codegen.ZodSchemaGenerator
end
