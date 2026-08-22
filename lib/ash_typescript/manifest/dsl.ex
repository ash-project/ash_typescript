# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Dsl do
  @moduledoc false

  use Spark.Dsl.Extension,
    transformers: [
      AshTypescript.Manifest.Transformers.BuildManifest,
      AshTypescript.Manifest.Transformers.DecorateManifest
    ],
    verifiers: [
      AshTypescript.Manifest.Verifiers.VerifyRpc,
      AshTypescript.Manifest.Verifiers.VerifyActionTypes,
      AshTypescript.Manifest.Verifiers.VerifyMappableTypes,
      AshTypescript.Manifest.Verifiers.VerifyUniqueInputFieldNames,
      AshTypescript.Manifest.Verifiers.VerifyMetadataFieldNames,
      AshTypescript.Manifest.Verifiers.VerifyTypedQueryFields,
      AshTypescript.Manifest.Verifiers.VerifyIdentities,
      AshTypescript.Manifest.Verifiers.VerifyRpcWarnings
    ]
end
