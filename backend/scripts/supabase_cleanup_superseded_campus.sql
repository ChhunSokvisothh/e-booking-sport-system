-- Review the row counts and take a Supabase backup before running this script.
-- These are legacy objects from the superseded Campus implementation.
-- IMPORTANT: keep public.core_owner_application (underscore-separated); it is a separate table.
-- No CASCADE is used, so unexpected dependencies will stop the relevant operation.

BEGIN;

-- Remove the legacy subscription table before its referenced application table.
DROP TABLE IF EXISTS public.core_ownersubscription;
DROP TABLE IF EXISTS public.core_ownerapplication;
DROP TABLE IF EXISTS public.core_campusphoto;

-- Remove the old Facility -> Campus foreign key and column before dropping Campus.
ALTER TABLE IF EXISTS public.core_facility
    DROP CONSTRAINT IF EXISTS core_facility_campus_id_7476a63c_fk_core_campus_id;

ALTER TABLE IF EXISTS public.core_facility
    DROP COLUMN IF EXISTS campus_id;

DROP TABLE IF EXISTS public.core_campus;

COMMIT;
