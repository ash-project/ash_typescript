# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Transformers.FoldArgumentConstraints do
  @moduledoc """
  Validates and folds each route argument's constraints against the argument
  type's constraint schema, exactly like Ash does for resource attributes and
  action arguments.

  This normalizes route arguments to the same shape as manifest inputs at the
  source: type constraint defaults (e.g. `allow_empty?: false, trim?: true`
  for strings) are made explicit, so every downstream consumer — the request
  handler's constraint application, TS type mapping, and the shared Zod/
  Valibot field composition in `SchemaCore` — sees identical data regardless
  of whether a field originated from an RPC action or a typed controller.

  Invalid constraints (typos, wrong option types) become compile-time errors,
  matching Ash's behavior for resource arguments.
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
      case fold_constraints(argument.type, argument.constraints || []) do
        {:ok, folded} ->
          {:cont, {:ok, [%{argument | constraints: folded} | acc]}}

        {:error, message} ->
          {:halt,
           {:error,
            Spark.Error.DslError.exception(
              module: module,
              path: [:typed_controller, route.name, :argument, argument.name],
              message:
                "Invalid constraints for argument `#{argument.name}` " <>
                  "(type #{inspect(argument.type)}): #{message}"
            )}}
      end
    end)
    |> case do
      {:ok, folded_arguments} -> {:ok, %{route | arguments: Enum.reverse(folded_arguments)}}
      {:error, error} -> {:error, error}
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
    validate_constraints(constraints, Ash.Type.constraints(type))
  end

  defp validate_constraints(constraints, schema) do
    case Spark.Options.validate(constraints, schema) do
      {:ok, folded} -> {:ok, folded}
      {:error, %{message: message}} -> {:error, message}
      {:error, error} -> {:error, inspect(error)}
    end
  end
end
