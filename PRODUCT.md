# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

The primary user is a professional photographer or content creator preparing many photo and video assets for stock marketplaces from a desktop workstation.

## Product Purpose

StockFlow turns a folder of local media into stock-ready submissions. The core job is to review assets, generate and edit metadata in batches, run quality checks, track workflow state, and upload approved files to stock marketplaces without moving between several disconnected tools.

## Positioning

The product connects local asset browsing, AI-assisted metadata generation, editorial metadata, quality control, CSV exchange, and stock upload state in one continuous desktop workflow.

## Operating Context

Users work with folders containing many photos and videos. The current workflow includes workspace folders, a media grid, single- and multi-selection, a detail/editor panel, search and filters, AI and editorial tagging, metadata import/export, QC, upload queues, history, analytics, and settings for stock credentials.

## Capabilities and Constraints

- Preserve the real workflow states: new, metadata ready, QC failed, ready to upload, uploaded, and submitted.
- Preserve current capabilities and product terminology even when navigation and layout change radically.
- The current implementation is a Flutter desktop application, with macOS as the evidenced shipping target. Support for additional desktop targets is an open decision.
- Generated concepts may reorganize the full application shell, navigation, workspace, inspector, upload/history, analytics, and settings.
- Commercial claims, customer logos, usage metrics, and unsupported capabilities must not be invented.

## Brand Commitments

- Preserve the product name `StockFlow` unless the user explicitly requests a rebrand.
- The existing icon and current blue identity are evidence, not binding visual authority for this redesign.
- The interface language is currently predominantly Russian, with established stock-industry terms such as AI, Editorial, CSV, QC, Adobe Stock, Shutterstock, FTPS, and SFTP.

## Evidence on Hand

- Current application shell and workflows: `lib/main.dart`.
- Main generation workspace: `lib/features/generation/presentation/generation_screen.dart` and its widget directory.
- Workflow model: `lib/models/workflow_status.dart`.
- Current theme: `lib/core/theme/app_theme.dart`.
- Upload, history, settings, and supporting documentation exist in the repository.
- No verified testimonials, customer logos, performance benchmarks, or commercial proof are available.

## Product Principles

1. Keep batch work faster than one-by-one editing.
2. Make the state of every asset and the next useful action immediately legible.
3. Treat preview, metadata, QC, and upload as one continuous production flow.
4. Preserve professional density without making the interface visually flat or monotonous.
5. Make destructive, irreversible, or externally transmitted actions explicit.

## Accessibility & Inclusion

Maintain strong text and status contrast, keyboard-accessible desktop workflows, visible focus states, non-color-only status communication, and support for both light and dark environments.
