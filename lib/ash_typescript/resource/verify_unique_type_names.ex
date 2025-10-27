# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.VerifyUniqueTypeNames do
  @moduledoc """
  Checks that all resources using AshTypescript.Resource have unique type_name values.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    current_resource = dsl[:persist][:module]

    first_typescript_resource =
      Mix.Project.config()[:app]
      |> Ash.Info.domains()
      |> Enum.find_value(fn domain ->
        domain
        |> Ash.Domain.Info.resources()
        |> Enum.find(&AshTypescript.Resource.Info.typescript_resource?/1)
      end)

    if current_resource == first_typescript_resource do
      all_type_names =
        Mix.Project.config()[:app]
        |> Ash.Info.domains()
        |> Enum.flat_map(fn domain ->
          domain
          |> Ash.Domain.Info.resources()
          |> Enum.filter(&AshTypescript.Resource.Info.typescript_resource?/1)
        end)
        |> Enum.uniq()
        |> Enum.map(fn resource ->
          type_name = AshTypescript.Resource.Info.typescript_type_name!(resource)
          {type_name, resource}
        end)

      # Group by type name to find duplicates
      duplicates =
        all_type_names
        |> Enum.group_by(&elem(&1, 0))
        |> Enum.filter(fn {_, resources} ->
          case resources do
            [_single] -> false
            _ -> true
          end
        end)
        |> Enum.map(fn {type_name, resources} ->
          resource_names =
            Enum.map(resources, fn {_, resource} ->
              resource |> to_string() |> String.trim("Elixir.")
            end)

          {type_name, resource_names}
        end)

      case duplicates do
        [] ->
          :ok

        _ ->
          duplicate_messages =
            Enum.map(duplicates, fn {type_name, resource_names} ->
              "Type name '#{type_name}' is used by: #{Enum.join(resource_names, ", ")}"
            end)

          {:error,
           Spark.Error.DslError.exception(
             message: """
             Duplicate TypeScript type names found:
             #{Enum.join(duplicate_messages, "\n")}

             Each resource using AshTypescript.Resource must have a unique type_name.
             """
           )}
      end
    else
      # For all other resources, just return :ok - the check is done by the first resource
      :ok
    end
  end
end
