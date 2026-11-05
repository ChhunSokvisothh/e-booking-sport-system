-- Run this once in the Supabase SQL Editor.
-- The bucket is private. Django creates short-lived upload/download URLs.
insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'profile-photos',
    'profile-photos',
    false,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Do not add a public SELECT policy.
-- Do not put the Supabase service-role key in Flutter.
