# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Transformers.FoldArgumentConstraints do
  @moduledoc """
  Validates and folds each route argument's constraints against the argument
  type's constraint schema, exactly like Ash does for resource attributes and
  action arguments.

  This normalizes route arguments to the same shape as manifest inputs at the
  source, by validating and then running `Ash.Type.init/2` as Ash does for
  action arguments: type constraint defaults (e.g. `allow_empty?: false,
  trim?: true` for strings) are made explicit and a NewType's own constraints
  are merged in, so every downstream consumer — the request
  handler's constraint application, TS type mapping, and the shared Zod/
  Valibot field composition in `SchemaCore` — sees identical data regardless
  of whether a field originated from an RPC action or a typed controller.

  A route's `returns` constraints are folded the same way, so result type
  generation sees the same normalized shape as a generic action's `returns`.
  The plain-data rule for argument and `returns` types is checked when the
  manifest compiles (`AshTypescript.Manifest.PlainData`).

  Invalid constraints (typos, wrong option types) and types that aren't Ash
  types become compile-time errors, matching Ash's behavior for resource
  arguments.
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.TypedController.Dsl.Route
  alias Spark.Dsl.Transformer

  @impl true
  def before?(AshTypescript.TypedController.Transformers.GenerateController), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)

    dsl_state
    |> Transformer.get_entities([:typed_controller])
    |> Enum.filter(&match?(%Route{}, &1))
    |> Enum.reduce_while({:ok, dsl_state}, fn route, {:ok, dsl_state} ->
      case fold_route(route, module) do
        {:ok, folded_route} ->
          dsl_state =
            Transformer.replace_entity(
              dsl_state,
              [:typed_controller],
              folded_route,
              &(match?(%Route{}, &1) and &1.name == route.name)
            )

          {:cont, {:ok, dsl_state}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp fold_route(%Route{arguments: arguments} = route, module) do
    arguments
    |> Enum.reduce_while({:ok, []}, fn argument, {:ok, acc} ->
      case fold(argument.type, argument.constraints || []) do
        {:ok, folded} ->
          {:cont, {:ok, [%{argument | constraints: folded} | acc]}}

        {:error, reason} ->
          path = [:typed_controller, route.name, :argument, argument.name]

          message =
            case reason do
              :invalid_type ->
                "Invalid type for argument `#{argument.name}`: " <>
                  "#{inspect(argument.type)} is not an Ash type"

              message ->
                "Invalid constraints for argument `#{argument.name}` " <>
                  "(type #{inspect(argument.type)}): #{message}"
            end

          {:halt, {:error, dsl_error(module, path, message)}}
      end
    end)
    |> case do
      {:ok, folded_arguments} ->
        fold_returns(%{route | arguments: Enum.reverse(folded_arguments)}, module)

      {:error, error} ->
        {:error, error}
    end
  end

  defp fold_returns(%Route{returns: nil} = route, _module), do: {:ok, route}

  defp fold_returns(%Route{returns: returns} = route, module) do
    case fold(returns, route.constraints) do
      {:ok, folded} ->
        {:ok, %{route | constraints: folded}}

      {:error, reason} ->
        message =
          case reason do
            :invalid_type ->
              "Invalid `returns` type for route `#{route.name}`: " <>
                "#{inspect(returns)} is not an Ash type"

            message ->
              "Invalid constraints for `returns` of route `#{route.name}` " <>
                "(type #{inspect(returns)}): #{message}"
          end

        {:error, dsl_error(module, [:typed_controller, route.name, :returns], message)}
    end
  end

  defp dsl_error(module, path, message),
    do: Spark.Error.DslError.exception(module: module, path: path, message: message)

  # Validate (folding in defaults), then `Ash.Type.init/2` — the same two steps
  # Ash runs for action arguments. `init` is what merges a NewType's own
  # constraints (e.g. its `fields`) and initializes nested field types, without
  # which casting would skip nested values.
  defp fold(type, constraints) do
    with {:ok, folded} <- fold_constraints(type, constraints) do
      Ash.Type.init(type, folded)
    end
  end

  defp fold_constraints({:array, inner_type}, constraints) do
    with {:ok, folded_items} <-
           fold_constraints(inner_type, Keyword.get(constraints, :items, [])),
         {:ok, folded} <-
           validate_constraints(
             Keyword.put(constraints, :items, folded_items),
             Ash.Type.constraints({:array, inner_type})
           ) do
      {:ok, Keyword.put(folded, :items, folded_items)}
    end
  end

  defp fold_constraints(type, constraints) do
    if Ash.Type.ash_type?(Ash.Type.get_type(type)) do
      validate_constraints(constraints, Ash.Type.constraints(type))
    else
      {:error, :invalid_type}
    end
  end

  defp validate_constraints(constraints, schema) do
    # `Spark.Options.validate/2` errors are always a `%Spark.Options.ValidationError{}`,
    # which always carries `:message` — so there is no other error shape to catch.
    case Spark.Options.validate(constraints, schema) do
      {:ok, folded} -> {:ok, folded}
      {:error, %{message: message}} -> {:error, message}
    end
  end
end
