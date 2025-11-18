# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen do
  @moduledoc """
  Main code generation module for TypeScript types and schemas from Ash resources.

  This module serves as the primary entry point for code generation. It delegates
  to specialized submodules in `AshTypescript.Codegen.*` for specific tasks:

  - `TypeDiscovery` - Discovers all types needing TypeScript definitions
  - `TypeAliases` - Generates TypeScript type aliases for Ash types
  - `ResourceSchemas` - Generates resource schemas (output and input)
  - `TypeMapper` - Maps Ash types to TypeScript types
  - `Helpers` - Shared utility functions
  """

  alias AshTypescript.Codegen.{
    Helpers,
    ResourceSchemas,
    TypeAliases,
    TypeDiscovery,
    TypeMapper
  }

  alias AshTypescript.TypeSystem.Introspection

  # Delegate resource discovery to TypeDiscovery
  defdelegate find_embedded_resources(otp_app), to: TypeDiscovery
  defdelegate find_typed_struct_modules(resources), to: TypeDiscovery
  defdelegate find_field_constrained_types(resources), to: TypeDiscovery

  # Delegate type alias generation to TypeAliases
  defdelegate generate_ash_type_aliases(resources, actions, otp_app), to: TypeAliases

  # Delegate schema generation to ResourceSchemas
  defdelegate generate_all_schemas_for_resources(resources, allowed_resources),
    to: ResourceSchemas

  defdelegate generate_all_schemas_for_resource(resource, allowed_resources), to: ResourceSchemas
  defdelegate generate_unified_resource_schema(resource, allowed_resources), to: ResourceSchemas
  defdelegate generate_input_schema(resource), to: ResourceSchemas

  # Delegate type mapping to TypeMapper
  defdelegate get_ts_type(type_and_constraints, select_and_loads \\ nil), to: TypeMapper
  defdelegate get_ts_input_type(attr), to: TypeMapper
  defdelegate build_map_type(fields, select \\ nil, field_name_mappings \\ nil), to: TypeMapper
  defdelegate build_union_type(types), to: TypeMapper
  defdelegate build_union_input_type(types), to: TypeMapper
  defdelegate build_resource_type(resource, select_and_loads \\ nil), to: TypeMapper
  defdelegate get_resource_field_spec(field, resource), to: TypeMapper

  # Delegate utility functions to Helpers
  defdelegate build_resource_type_name(resource_module), to: Helpers
  defdelegate is_simple_calculation(calc), to: Helpers
  defdelegate is_complex_return_type(type, constraints), to: Helpers
  defdelegate lookup_aggregate_type(resource, relationship_path, field), to: Helpers

  # Delegate type introspection to TypeSystem.Introspection
  defdelegate is_embedded_resource?(module), to: Introspection
  defdelegate unwrap_new_type(type, constraints), to: Introspection
end
