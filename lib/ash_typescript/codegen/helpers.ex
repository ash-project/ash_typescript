# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.Helpers do
  @moduledoc """
  Shared helper functions for code generation.
  """

  @doc """
  Builds a TypeScript type name from a resource module.
  Uses the custom typescript_type_name if defined, otherwise derives from module name.
  """
  def build_resource_type_name(resource_module) do
    case AshTypescript.Manifest.Custom.type_name(
           AshTypescript.Manifest.Custom.resolve_resource(resource_module)
         ) do
      name when is_binary(name) ->
        name

      _ ->
        derive_resource_type_name(resource_module)
    end
  end

  defp derive_resource_type_name(resource_module) do
    case AshTypescript.Resource.Info.typescript_type_name(resource_module) do
      {:ok, name} ->
        name

      _ ->
        resource_module
        |> Module.split()
        |> then(fn [first | rest] = list ->
          if first == "Elixir" do
            Enum.join(rest, "")
          else
            Enum.join(list, "")
          end
        end)
    end
  end

  @doc """
  Whether codegen emits `relationship` (in resource schemas, and so in field
  selection, and in filter types, restricted schemas and the JSON manifest): only
  when its destination is an exposed resource. The runtime rejects selecting or
  filtering through any other relationship (`unknown_field`).
  """
  def exposed_relationship?(
        %Ash.Info.Manifest.Relationship{destination: destination},
        resource_lookup \\ AshTypescript.resource_lookup()
      ) do
    resource_lookup
    |> Ash.Info.Manifest.get_resource(destination)
    |> AshRpc.Manifest.Custom.exposed?()
  end

  @doc """
  Whether a resource gets filter and sort types: only exposed ones do. An
  unexposed resource (a struct argument, or an embedded resource the mapping
  source doesn't expose) is used only as a value, so nothing references its
  filter or sort types.
  """
  def filter_and_sort_types?(%Ash.Info.Manifest.Resource{} = resource),
    do: AshRpc.Manifest.Custom.exposed?(resource)

  @doc """
  Converts a PascalCase name to camelCase by lowercasing the first character.

  ## Examples

      iex> AshTypescript.Codegen.Helpers.camel_case_prefix("Todo")
      "todo"

      iex> AshTypescript.Codegen.Helpers.camel_case_prefix("OrgTodo")
      "orgTodo"
  """
  def camel_case_prefix(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end
end
