-- Run in Supabase SQL Editor only after taking a database backup.
-- This removes objects introduced by the superseded Campus implementation.
-- It intentionally avoids CASCADE so unexpected dependencies stop the script.

ALTER TABLE IF EXISTS public.core_facility
    DROP COLUMN IF EXISTS campus_id;

DROP TABLE IF EXISTS public.core_campusphoto;
DROP TABLE IF EXISTS public.core_ownersubscription;
DROP TABLE IF EXISTS public.core_campus;
DROP TABLE IF EXISTS public.core_ownerapplication;
