# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.ParallelCompileReachabilityTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:warn_on_non_rpc_references])
    Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)
  end

  @sources %{
    "domain.ex" => """
    defmodule AshTypescript.Test.CompileRace.Domain do
      use Ash.Domain, extensions: [AshTypescript.Rpc], validate_config_inclusion?: false

      typescript_rpc do
        resource AshTypescript.Test.CompileRace.Root do
          rpc_action :list_roots, :read
        end
      end

      resources do
        resource AshTypescript.Test.CompileRace.Root
        resource AshTypescript.Test.CompileRace.Middle
        resource AshTypescript.Test.CompileRace.Leaf
      end
    end
    """,
    "root.ex" => """
    defmodule AshTypescript.Test.CompileRace.Root do
      use Ash.Resource,
        domain: AshTypescript.Test.CompileRace.Domain,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "CompileRaceRoot"
      end

      attributes do
        uuid_primary_key :id
      end

      relationships do
        has_many :middles, AshTypescript.Test.CompileRace.Middle, public?: true
      end

      actions do
        defaults [:read]
      end
    end
    """,
    # Holds the middle resource back so it is still compiling while the
    # manifest's reachability walk reaches it through Root.
    "middle.ex" => """
    Process.sleep(500)

    defmodule AshTypescript.Test.CompileRace.Middle do
      use Ash.Resource,
        domain: AshTypescript.Test.CompileRace.Domain,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "CompileRaceMiddle"
      end

      attributes do
        uuid_primary_key :id
      end

      relationships do
        belongs_to :root, AshTypescript.Test.CompileRace.Root, public?: true
        has_many :leaves, AshTypescript.Test.CompileRace.Leaf, public?: true
      end

      actions do
        defaults [:read]
      end
    end
    """,
    "leaf.ex" => """
    defmodule AshTypescript.Test.CompileRace.Leaf do
      use Ash.Resource,
        domain: AshTypescript.Test.CompileRace.Domain,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "CompileRaceLeaf"
      end

      attributes do
        uuid_primary_key :id
      end

      relationships do
        belongs_to :middle, AshTypescript.Test.CompileRace.Middle, public?: true
      end

      actions do
        defaults [:read]
      end
    end
    """,
    "manifest.ex" => """
    defmodule AshTypescript.Test.CompileRace.Manifest do
      use AshTypescript.Manifest,
        otp_app: :ash_typescript,
        domains: [AshTypescript.Test.CompileRace.Domain]
    end
    """
  }

  test "resources behind a still-compiling resource reach the persisted lookup", %{
    tmp_dir: tmp_dir
  } do
    files =
      for {name, source} <- @sources do
        path = Path.join(tmp_dir, name)
        File.write!(path, source)
        path
      end

    assert {:ok, _modules, _warnings} =
             Kernel.ParallelCompiler.compile(files, return_diagnostics: true)

    lookup = AshTypescript.resource_lookup(AshTypescript.Test.CompileRace.Manifest)

    assert Map.has_key?(lookup, AshTypescript.Test.CompileRace.Middle)
    assert Map.has_key?(lookup, AshTypescript.Test.CompileRace.Leaf)
  end
end
