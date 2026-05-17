# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.SortTypes do
  @moduledoc """
  Generates TypeScript sort field `as const` arrays and derived union types for Ash resources.

  Each resource gets:
  - `{resourceName}SortFields` — a runtime `as const` array of sortable field names
  - `{ResourceName}SortField` — a union type derived from the array

  Sortable fields are driven by `Ash.Info.Manifest`: any field whose
  `sortable?` is `true` is included, formatted for the client (e.g. camelCase).
  """

  alias AshTypescript.Codegen.Helpers

  def generate_sort_types(resources, resource_lookup) when is_list(resources) do
    Enum.map_join(resources, "\n", &generate_sort_type(&1, resource_lookup))
  end

  def generate_sort_type(resource, resource_lookup) when is_map(resource_lookup) do
    case Map.get(resource_lookup, resource) do
      %Ash.Info.Manifest.Resource{} = api_resource ->
        do_generate_sort_type(resource, api_resource)

      nil ->
        raise "SortTypes: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  # Convenience forms — fall back to the cached resource lookup
  def generate_sort_types(resources) when is_list(resources) do
    generate_sort_types(resources, AshTypescript.resource_lookup())
  end

  def generate_sort_type(resource) do
    generate_sort_type(resource, AshTypescript.resource_lookup())
  end

  defp do_generate_sort_type(resource, api_resource) do
    resource_name = Helpers.build_resource_type_name(resource)
    formatter = AshTypescript.Rpc.output_field_formatter()

    fields =
      api_resource
      |> Ash.Info.Manifest.Resource.all_fields()
      |> Enum.filter(& &1.sortable?)
      |> Enum.map(
        &AshTypescript.FieldFormatter.format_field_for_client(&1.name, resource, formatter)
      )

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
