# Project Change Log (2026-04-08)

## Scope
This document summarizes major updates applied to booking consistency, owner management, archive retention, and quick booking experience.

## Progress Update (2026-04-20)

### Backend
- Extended chatbot payment follow-up handling so phrases like "I paid" can trigger booking payment-status verification.
- Improved chat booking search consistency by prioritizing fallback parser values (date/time/venue) when extractor output drifts.
- Strengthened venue extraction to support prompts without prepositions and reduce stale context carry-over.
- Tightened fuzzy venue resolution to ignore generic sport tokens and require higher confidence for near matches.

### Flutter
- Updated quick booking flow and slot handling to align chat previews and receipt timing logic.
- Refined chatbot bottom-sheet behaviors for booking confirmations and follow-up responses.
- Adjusted owner home shell interactions to keep owner-facing booking/venue actions consistent with backend responses.

### Validation Notes
- This update reflects work committed on branch main in commit bb286dc.
- Existing 2026-04-08 notes remain valid and are kept below as historical context.

## Backend Changes

### 1) Slot consistency and booking lock behavior
- Standardized slot availability reads to use Django database as source of truth.
- Strengthened slot booking logic to prevent double booking across different user accounts.
- Added stricter checks in pending and confirmed booking flows.
- Updated slot state transitions for reserve, confirm, cancel, and expiry release.

### 2) Owner booking visibility for analytics
- Owner-facing booking queries now return records scoped to owner facilities.
- Preserved legacy visibility for records tied to unassigned owner fields when needed.

### 3) Archive retention and lookup support (3 months)
- Facility archive retention set to 90 days.
- Added owner archive lookup filters:
  - archived_only
  - q (search)
  - archived_from
  - archived_to
- Added cleanup behavior for archived facilities older than retention period when they have no linked bookings.

### 4) Owner facility endpoints
- Improved owner facility listing logic for active/archived records and filtered retrieval.

## Frontend Changes

### 1) Owner management improvements
- Owner venues now use owner-specific provider flow for better consistency.
- Added venue search in Owner Venues screen (name/location/sport).
- Added new Archive Records screen with date-range search and refresh.
- Added formal sync message in Owner dashboard:
  - "Records are being prepared."
  - "Records were updated at HH:mm:ss."

### 2) Quick Booking updates
- Date selector now includes Today and defaults to Today.
- Can re-select Today after moving to other dates.
- Removed per-time slot text labels (Open/Selected/Booked/Reserved) from chip text.
- Slot color states remain to indicate status visually.

## Repo Hygiene Changes
- Added ignore rules for local runtime artifacts.
- Untracked local SQLite database file to avoid accidental commits.

## Files/Folders Added (high-level)
- docs/
- owner archive records screen
- additional provider/controller updates
- backend migration files for coupon/facility archive evolution

## Notes for Team
- Run backend migrations before testing if environment is new.
- Use owner archive filters to inspect archived records within retention period.
- Verify cross-account booking consistency by testing the same slot from two accounts.
