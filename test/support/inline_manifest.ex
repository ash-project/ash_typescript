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
  output goes to a stderr capture.
  """

  @spec build!(keyword()) :: Ash.Info.Manifest.t()
  def build!(opts) do
    module = module_for(opts)
    opts = Keyword.put_new(opts, :otp_app, :ash_typescript)

    :global.trans({__MODULE__, module}, fn ->
      unless Code.ensure_loaded?(module) do
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Module.create(
            module,
            quote(do: use(AshTypescript.Manifest, unquote(opts))),
            Macro.Env.location(__ENV__)
          )
        end)
      end
    end)

    AshTypescript.manifest(module)
  end

  @spec module_for(keyword()) :: module()
  def module_for(opts) do
    opts = Keyword.put_new(opts, :otp_app, :ash_typescript)
    Module.concat([__MODULE__, "M#{:erlang.phash2(opts)}"])
  end
end
