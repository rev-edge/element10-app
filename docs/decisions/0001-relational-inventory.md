# ADR 0001 — Inventory system of record: relational rows (D1)

**Date:** 2026-07-14 · **Status:** accepted, implemented (Chain M → M4)

## Context
Inventory lived as a JSONB array inside the `shared` `e10_workspace` row, shadowed by an append-only ledger. Every write rewrote the whole ~6 KB blob (write amplification) and a concurrent edit to any item was a section-level conflict (H2's merge granularity is the section). The storage spike (`docs/SPIKE_storage_decision.md`) priced three options.

## Decision
Migrate inventory to relational rows: `e10_inventory_items` (PK = the existing stable text id — the ledger already keys on it 1:1, no renumbering) + `e10_inventory_reservations` (child rows). Every mutation is a single-transaction SECURITY DEFINER RPC (validate → mutate rows → append ledger movement → commit), mutation-level idempotent. Staged dual-write with a documented rollback.

## Why
Spike's own rule: 2.8 (reservation lifecycle) is the point where the nested-array model actively hurts, and it was imminent. Reservations are the strongest relational case (per-row lifecycle, joins, independent RLS). Per-row realtime removes the section-conflict ceiling.

## Consequences
Chain M (M1 schema+shadow → M2 RPCs → M3 client cutover → M4 blob retirement). Async reads or a client cache (accepted: the in-memory `S.inventory` array, patched per-row by realtime). See ADR 0002.
