# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.VerifierChecker do
  @moduledoc """
  Checks if any verifiers have failed for resources and domains.

  This is needed because Spark verifiers now emit warnings instead of errors,
  so we need to re-run them during codegen to detect issues.
  """

  @doc """
  Checks all verifiers for a list of modules (resources/domains).
  Returns :ok or {:error, formatted_message}
  """
  def check_all_verifiers(modules) do
    errors =
      modules
      |> Enum.flat_map(&check_module_verifiers/1)

    case errors do
      [] -> :ok
      errors -> {:error, format_verifier_errors(errors)}
    end
  end

  defp check_module_verifiers(module) do
    extensions = Spark.extensions(module)
    dsl_config = module.spark_dsl_config()

    ash_typescript_extensions = [AshTypescript.Resource, AshTypescript.Rpc]

    extensions
    |> Enum.filter(&(&1 in ash_typescript_extensions))
    |> Enum.flat_map(fn extension ->
      Code.ensure_loaded!(extension)

      if function_exported?(extension, :verifiers, 0) do
        extension.verifiers()
      else
        []
      end
    end)
    |> Enum.flat_map(fn verifier ->
      check_single_verifier(module, verifier, dsl_config)
    end)
  end

  defp check_single_verifier(module, verifier, dsl_config) do
    case verifier.verify(dsl_config) do
      :ok ->
        []

      {:warn, warnings} ->
        warnings_list = List.wrap(warnings)

        Enum.map(warnings_list, fn warning ->
          {module, verifier, warning}
        end)

      {:error, error} ->
        [{module, verifier, error}]
    end
  rescue
    e -> [{module, verifier, e}]
  end

  defp format_verifier_errors(errors) do
    errors
    |> Enum.map_join("\n\n", fn {module, verifier, error} ->
      """
      Module: #{inspect(module)}
      Verifier: #{inspect(verifier)}
      Error: #{format_error(error)}
      """
      |> String.trim()
    end)
  end

  defp format_error(%Spark.Error.DslError{message: message}), do: message
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: Exception.message(error)
end
