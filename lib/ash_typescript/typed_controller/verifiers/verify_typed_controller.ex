# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Verifiers.VerifyTypedController do
  @moduledoc """
  Verifies that typed controller configurations are valid.

  Checks:
  1. Route names are unique
  2. Each route has a `run` handler
  3. Argument types are valid Ash types
  4. Route and argument names are valid for TypeScript generation (no `_1`, `?` patterns)
  5. Field names inside `returns` and argument types (typed maps, keywords,
     tuples, structs — at any depth) are valid for TypeScript generation too.
     Handlers send and receive these as-is, so an invalid name would produce a
     generated type that doesn't match the wire. A type's own
     `typescript_field_names/0` mapping is honored, as for RPC.
  """
  use Spark.Dsl.Verifier

  alias Ash.Info.Manifest.Generator.TypeResolver
  alias Ash.Info.Manifest.Type
  alias AshTypescript.NameValidation
  alias AshTypescript.TypeSystem.Introspection

  @impl true
  def verify(dsl) do
    routes = Spark.Dsl.Verifier.get_entities(dsl, [:typed_controller])

    with :ok <- verify_unique_route_names(routes),
         :ok <- verify_routes_have_handlers(routes),
         :ok <- verify_argument_types(routes),
         :ok <- verify_names_for_typescript(routes) do
      verify_field_names_for_typescript(routes)
    end
  end

  defp verify_unique_route_names(routes) do
    duplicates =
      routes
      |> Enum.group_by(& &1.name)
      |> Enum.filter(fn {_, v} -> length(v) > 1 end)
      |> Enum.map(fn {name, _} -> name end)

    if duplicates == [] do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message:
           "Duplicate route names found: #{Enum.map_join(duplicates, ", ", &inspect/1)}. " <>
             "Each route must have a unique name."
       )}
    end
  end

  defp verify_routes_have_handlers(routes) do
    missing =
      Enum.filter(routes, fn route -> is_nil(route.run) end)

    if missing == [] do
      :ok
    else
      names = Enum.map_join(missing, ", ", &inspect(&1.name))

      {:error,
       Spark.Error.DslError.exception(
         message: "Routes without handlers: #{names}. Each route must have a `run` option."
       )}
    end
  end

  defp verify_argument_types(routes) do
    invalid =
      routes
      |> Enum.flat_map(fn route ->
        Enum.flat_map(route.arguments, fn arg ->
          type = resolve_type(arg.type)

          if Ash.Type.get_type(type) do
            []
          else
            [{route.name, arg.name, arg.type}]
          end
        end)
      end)

    if invalid == [] do
      :ok
    else
      details =
        Enum.map_join(invalid, "\n", fn {route_name, arg_name, type} ->
          "  - route #{inspect(route_name)}, argument #{inspect(arg_name)}: #{inspect(type)}"
        end)

      {:error,
       Spark.Error.DslError.exception(message: "Invalid argument types found:\n\n#{details}")}
    end
  end

  defp resolve_type({type, _constraints}), do: type
  defp resolve_type(type), do: type

  defp verify_names_for_typescript(routes) do
    invalid =
      Enum.flat_map(routes, fn route ->
        route_error = name_error("route #{inspect(route.name)}", route.name)

        argument_errors =
          Enum.flat_map(route.arguments, fn arg ->
            name_error("route #{inspect(route.name)}, argument #{inspect(arg.name)}", arg.name)
          end)

        route_error ++ argument_errors
      end)

    if invalid == [] do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message: """
         Invalid names for TypeScript generation found.
         Names containing question marks or numbers preceded by underscores produce \
         awkward camelCase identifiers, and names that aren't valid identifiers can't \
         be generated at all.

         #{Enum.join(invalid, "\n")}
         """
       )}
    end
  end

  defp name_error(subject, name) do
    case name_problem(name) do
      :invalid_name ->
        ["  - #{subject} → consider renaming to :#{NameValidation.make_name_better(name)}"]

      :not_identifier ->
        ["  - #{subject} is not a valid TypeScript identifier → rename it"]

      nil ->
        []
    end
  end

  defp name_problem(name) do
    cond do
      NameValidation.invalid_name?(name) -> :invalid_name
      not NameValidation.identifier?(name) -> :not_identifier
      true -> nil
    end
  end

  defp verify_field_names_for_typescript(routes) do
    invalid =
      for route <- routes,
          {location, type, constraints} <- typed_values(route),
          error <- invalid_fields(TypeResolver.resolve(type, constraints), [], []) do
        format_field_error("route #{inspect(route.name)}, #{location} field", error)
      end

    if invalid == [] do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message: """
         Invalid field names found in typed controller route types.
         Route bodies are sent as-is, so field names must be valid TypeScript \
         identifiers, without question marks or numbers preceded by underscores.

         #{Enum.join(invalid, "\n")}
         """
       )}
    end
  end

  defp format_field_error(subject, {:invalid_name, path, name}),
    do:
      "  - #{subject} `#{Enum.join(path, ".")}` → consider renaming to " <>
        ":#{NameValidation.make_name_better(name)}"

  defp format_field_error(subject, {:not_identifier, path}),
    do:
      "  - #{subject} `#{Enum.join(path, ".")}` is not a valid TypeScript identifier → rename it"

  defp format_field_error(subject, {:invalid_mapping, path, mapped, module}),
    do:
      "  - #{subject} `#{Enum.join(path, ".")}` is mapped to #{inspect(mapped)} by " <>
        "#{inspect(module)}.typescript_field_names/0 → fix the mapping"

  defp typed_values(route) do
    returns = if route.returns, do: [{"returns", route.returns, route.constraints}], else: []

    returns ++
      Enum.map(route.arguments, &{"argument #{inspect(&1.name)}", &1.type, &1.constraints || []})
  end

  # Walks the same shape `TypeMapper.map_route_result_type/2` renders, so the
  # names checked are exactly the client names generated. `seen` guards against
  # recursive named types on the current branch.
  defp invalid_fields(%Type{kind: :type_ref, module: module}, path, seen) do
    if module in seen do
      []
    else
      module
      |> TypeResolver.resolve_definition()
      |> invalid_fields(path, [module | seen])
    end
  end

  defp invalid_fields(%Type{kind: :array, item_type: item_type}, path, seen),
    do: invalid_fields(item_type, path ++ ["[]"], seen)

  defp invalid_fields(%Type{kind: :union, members: members}, path, seen) when is_list(members) do
    Enum.flat_map(members, &invalid_fields(&1.type, path, seen))
  end

  defp invalid_fields(%Type{kind: kind} = type, path, seen)
       when kind in [:map, :keyword, :tuple, :struct] do
    mapping_module = mapping_module(type)
    mappings = Introspection.get_typescript_field_names_map(mapping_module)

    Enum.flat_map(Type.get_fields(type), fn %{name: name, type: field_type} ->
      field_path = path ++ [to_string(name)]

      field_name_error(field_path, name, Map.fetch(mappings, name), mapping_module) ++
        invalid_fields(field_type, field_path, seen)
    end)
  end

  defp invalid_fields(_type, _path, _seen), do: []

  defp field_name_error(path, _name, {:ok, mapped}, mapping_module) do
    if name_problem(mapped),
      do: [{:invalid_mapping, path, mapped, mapping_module}],
      else: []
  end

  defp field_name_error(path, name, :error, _mapping_module) do
    case name_problem(name) do
      :invalid_name -> [{:invalid_name, path, name}]
      :not_identifier -> [{:not_identifier, path}]
      nil -> []
    end
  end

  # Mirrors TypeMapper: structs only take mappings from an explicit
  # `instance_of` module.
  defp mapping_module(%Type{kind: :struct, instance_of: module}), do: module
  defp mapping_module(type), do: Type.effective_module(type)
end
