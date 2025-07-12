# AshTypescript Overview

## Purpose
AshTypescript generates TypeScript types and RPC clients from Ash resources and actions, ensuring type safety between Elixir backend and TypeScript frontend.

## Core Architecture

### Main Components
- **AshTypescript.Codegen**: Core type generation engine
- **AshTypescript.Rpc**: DSL extension for exposing resources via RPC
- **AshTypescript.Rpc.Codegen**: RPC client and endpoint generation
- **Mix.Tasks.AshTypescript.Codegen**: CLI interface

### Generated Output
- TypeScript type definitions for resources (attributes, relationships, calculations, aggregates)
- RPC client functions for calling Ash actions
- Base type aliases for Ash types (UUID, DateTime, etc.)
- Type-safe request/response interfaces

## Key Concepts

### Resource Schema Generation
- **Attributes**: Direct mapping to TypeScript types
- **Relationships**: Referenced as foreign keys or nested objects
- **Calculations**: Computed fields with proper typing
- **Aggregates**: Summary fields (counts, sums, etc.)

### RPC Action Exposure
- Resources opt-in to RPC via `AshTypescript.Rpc` DSL
- Actions exposed as TypeScript functions
- Automatic request validation and response typing
- Support for filters, sorting, pagination

### Type Safety
- All Ash types mapped to appropriate TypeScript equivalents
- Union types for enums and polymorphic fields
- Optional vs required field handling
- Error type definitions

## File Output
- Default: `assets/js/ash_rpc.ts`
- Configurable via `--output` flag or app config
- Single file containing all types and RPC clients
- Generated file includes warning header

## Integration Points
- **Phoenix**: RPC endpoints at `/rpc/run` and `/rpc/validate`
- **Frontend**: Import generated types and client functions
- **Testing**: TypeScript compilation verification in test suite
- **Development**: Watch mode for automatic regeneration