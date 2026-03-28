# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.SortTypes do
  @moduledoc """
  Generates TypeScript sort field `as const` arrays and derived union types for Ash resources.

  Each resource gets:
  - `{resourceName}SortFields` — a runtime `as const` array of sortable field names
  - `{ResourceName}SortField` — a union type derived from the array

  Sortable fields include public attributes, calculations with `field?: true`,
  and all public aggregates, formatted for the client (e.g. camelCase).
  """

  alias AshTypescript.Codegen.Helpers

  def generate_sort_types(resources) when is_list(resources) do
    Enum.map_join(resources, "\n", &generate_sort_type/1)
  end

  def generate_sort_type(resource) do
    resource_name = Helpers.build_resource_type_name(resource)

    fields = Helpers.client_field_names(resource)

    if fields == [] do
      ""
    else
      const_name = Helpers.camel_case_prefix(resource_name) <> "SortFields"
      type_name = "#{resource_name}SortField"
      array_items = Enum.map_join(fields, ", ", &"\"#{&1}\"")

      """
      export const #{const_name} = [#{array_items}] as const;
      export type #{type_name} = (typeof #{const_name})[number];
      """
    end
  end
end
