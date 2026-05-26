# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.VerifierChecker do
  @moduledoc """
  Re-runs per-module Spark verifiers for the AshTypescript Resource and Rpc
  extensions. Spark emits warnings (rather than raising) when a verifier fails;
  during codegen we want to promote those warnings to hard errors. This module
  iterates the configured verifiers for each module and aggregates failures.

  Manifest-level verifiers are *not* run here — they're a property of the
  `AshTypescript.Manifest` module and are checked at compile time by Spark, and
  re-checked at codegen time via `AshTypescript.Manifest.run_verifiers/1` (or
  `verify_for_domains/2` for inline test manifests).
  """

  @doc """
  Checks per-module Resource/Rpc extension verifiers for a list of modules.
  Returns `:ok` or `{:error, formatted_message}`.
  """
  def check_all_verifiers(modules) do
    case Enum.flat_map(modules, &check_module_verifiers/1) do
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
