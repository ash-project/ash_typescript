# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InlineManifest do
  @moduledoc """
  Builds an `AshTypescript.Manifest` module at runtime, once per distinct
  option set, and returns its decorated manifest. Use it for fixtures
  (typed controllers, channels, domains) that are defined in test files and
  kept out of the app config. The module name is derived from the options,
  so repeated calls reuse the compiled module. Compiler and verifier
  output goes to a stderr capture, and is attached to the error when the
  module fails to compile.

  `body:` is quoted DSL for the module body (a `custom_types` section);
  the other options go to `use AshTypescript.Manifest`. It defaults to the
  test manifest's `custom_types` entries (`app_custom_types/0`): a manifest
  over the test app reaches its custom types (`GeoPoint`, `LineItem`,
  `TodoRef`, `CustomIdentifier`, `ExternalCode`), which decoration and codegen
  can't map without them.
  Pass `body: nil` for a manifest without a `custom_types` section.
  """

  @spec build!(keyword()) :: Ash.Info.Manifest.t()
  def build!(opts) do
    module = module_for(opts)
    {body, opts} = Keyword.pop(opts, :body, app_custom_types())
    opts = Keyword.put_new(opts, :otp_app, :ash_typescript)

    # The lock id is `{resource, requester}`: a per-process requester, so
    # concurrent async callers wait for each other instead of sharing the lock.
    :global.trans({{__MODULE__, module}, self()}, fn ->
      unless Code.ensure_loaded?(module) do
        {result, stderr} =
          ExUnit.CaptureIO.with_io(:stderr, fn ->
            try do
              Module.create(
                module,
                quote do
                  use AshTypescript.Manifest, unquote(opts)
                  unquote(body)
                end,
                Macro.Env.location(__ENV__)
              )

              :ok
            rescue
              error -> {:error, error, __STACKTRACE__}
            end
          end)

        with {:error, error, stacktrace} <- result do
          reraise RuntimeError,
                  [
                    message:
                      "InlineManifest.build!(#{inspect(opts)}) failed: " <>
                        Exception.message(error) <> "\n\nCompiler output:\n" <> stderr
                  ],
                  stacktrace
        end
      end
    end)

    AshTypescript.manifest(module)
  end

  @doc "The test manifest's `custom_types` section (`test/support/manifest.ex`), quoted."
  @spec app_custom_types() :: Macro.t()
  def app_custom_types do
    quote do
      custom_types do
        scalar AshTypescript.Test.CustomIdentifier, :string do
          zod "CustomZodSchemas.objectId"
          valibot "CustomValibotSchemas.objectId"
        end

        scalar AshTypescript.Test.ExternalCode, :string do
          ts_type {AshTypescript.Test.ExternalCodeTs, :typescript, []}
          zod {AshTypescript.Test.ExternalCodeTs, :zod, []}
          valibot {AshTypescript.Test.ExternalCodeTs, :valibot, []}
        end

        map AshTypescript.Test.GeoPoint do
          ts_alias "GeoPoint"
          field :lat, :float, allow_nil?: false
          field :lng, :float, allow_nil?: false
          zod "NestedZodSchemas.geoPoint"
          valibot "NestedValibotSchemas.geoPoint"
        end

        # A declared type with a nested declared type and an embedded resource.
        map AshTypescript.Test.LineItem do
          ts_alias "LineItem"
          field :label, :string, allow_nil?: false
          field :price, AshMoney.Types.Money, allow_nil?: false
          field :meta, AshTypescript.Test.TaskMetadata
        end

        # A declared type with a non-embedded resource field, only returned.
        map AshTypescript.Test.TodoRef do
          field :todo, :struct, constraints: [instance_of: AshTypescript.Test.Todo]
        end

        # A field-bearing NewType opted in by a field-less entry (joined name).
        map AshTypescript.Test.TodoTimestamp
      end
    end
  end

  @spec module_for(keyword()) :: module()
  def module_for(opts) do
    opts = Keyword.put_new(opts, :otp_app, :ash_typescript)
    Module.concat([__MODULE__, "M#{:erlang.phash2(opts)}"])
  end
end
