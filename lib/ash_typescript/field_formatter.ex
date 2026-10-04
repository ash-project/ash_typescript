# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FieldFormatter do
  @moduledoc """
  Codegen-side field naming. Resolves resource and type *modules* (which is
  what codegen walks) to the names ash_rpc uses at runtime, falling back to
  `field_names` / `typescript_field_names/0` for modules the manifest doesn't
  carry (e.g. typed-controller-only types). Everything else delegates to
  `AshRpc.FieldFormatter`.
  """

  alias AshTypescript.Helpers

  defdelegate format_field_name(field, formatter), to: AshRpc.FieldFormatter
  defdelegate parse_input_field(field, formatter), to: AshRpc.FieldFormatter

  def format_field_for_client(field, resource_or_type \\ nil, formatter)

  def format_field_for_client(field, module, formatter)
      when is_atom(field) and is_atom(module) and not is_nil(module) do
    cond do
      Helpers.has_typescript_field_names?(module) ->
        Map.get(Helpers.typescript_field_names(module), field) ||
          AshRpc.FieldFormatter.format_field_name(field, formatter)

      AshTypescript.RpcMappingSource.exposed_resource?(module) ->
        case AshTypescript.Resource.Info.get_mapped_field_name(module, field) do
          mapped when is_binary(mapped) -> mapped
          _ -> AshRpc.FieldFormatter.format_field_name(field, formatter)
        end

      true ->
        AshRpc.FieldFormatter.format_field_name(field, formatter)
    end
  end

  def format_field_for_client(field, other, formatter),
    do: AshRpc.FieldFormatter.format_field_for_client(field, other, formatter)
end
