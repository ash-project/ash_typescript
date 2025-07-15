# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive embedded resources support with relationship-like architecture
- Schema key-based type inference system for accurate calculation type detection
- Enhanced field selection with unified object notation
- Complete TypeScript type safety for embedded resource calculations
- Strategic debug outputs for complex field processing issues
- Aggregate field support in field selection and embedded resources

### Changed
- **BREAKING**: Removed `calculations` parameter in favor of unified field format
- **BREAKING**: Embedded resources now use relationship-like syntax instead of separate sections
- Improved type inference to only include `fields` property for calculations returning resources
- Enhanced field parser to handle nested calculations within field lists
- Unified field format eliminates backwards compatibility complexity

### Fixed
- Type inference system no longer incorrectly assumes all complex calculations need `fields` property
- Aggregate fields now correctly route to `load` instead of `select` (fixes "No such attribute" errors)
- Embedded resource calculations now work properly with dual-nature processing
- Field classification now handles all 5 field types correctly (attributes, calculations, aggregates, relationships, embedded resources)
- Schema generation now conditionally includes `fields` property based on calculation return types

### Removed
- **BREAKING**: Backwards compatibility for separate `calculations` parameter
- ~300 lines of dual processing code for cleaner architecture
- Legacy embedded resource detection patterns

## [0.1.0] - Initial Release

### Added
- Basic TypeScript type generation from Ash resources
- RPC client generation with type-safe function calls
- Support for standard Ash types and constraints
- Field selection capabilities
- Multitenancy support
- Basic calculation support