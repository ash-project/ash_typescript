# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessor do
  @moduledoc """
  Processes requested fields for Ash resources, determining which fields should be selected
  vs loaded, and building extraction templates for result processing.

  This module handles different action types:
  - CRUD actions (:read, :create, :update, :destroy) return resource records
  - Generic actions (:action) return arbitrary types as specified in their `returns` field

  ## Architecture

  Delegates to `FieldSelector`, which uses a unified type-driven recursive
  dispatch pattern (similar to `ValueFormatter`). Each type is self-describing
  via `{type, constraints}`, so no separate classification step is needed.

  ## Manifest module

  Field selection needs lookups (`resources`, `actions`, `types`) that live on
  an `AshTypescript.Manifest` module's persisted Spark DSL state.
  `process/4` accepts an optional manifest module — when omitted, defaults to
  `AshTypescript.manifest_module/0` (the configured production manifest).
  Verifiers running against an inline test manifest pass their own module.
  """

  alias AshTypescript.Rpc.FieldProcessing.{Atomizer, FieldSelector}

  @doc """
  Atomizes requested fields by converting standalone strings to atoms and map keys to atoms.
  """
  defdelegate atomize_requested_fields(requested_fields, resource \\ nil), to: Atomizer

  @doc """
  Processes requested fields for a given resource and action.

  Returns `{:ok, {select_fields, load_fields, extraction_template}}` or `{:error, error}`.
  """
  def process(resource, action_name, requested_fields, manifest_module \\ nil) do
    FieldSelector.process(
      resource,
      action_name,
      requested_fields,
      manifest_module || AshTypescript.manifest_module()
    )
  end
end
