# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.AshApiSpec.Dsl do
  @moduledoc false

  use Spark.Dsl.Extension,
    transformers: [AshTypescript.AshApiSpec.Transformers.BuildAppSpec]
end
