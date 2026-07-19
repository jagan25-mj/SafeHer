-- ============================================================
-- SafeHer – Supabase Production Schema
-- ============================================================
-- Run this in the Supabase SQL Editor to create all tables,
-- indexes, and Row Level Security (RLS) policies.
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('user', 'admin');
    END IF;
END$$;

-- ──────────────────────────────────────────────────────────────
-- 2. Profiles
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS profiles (
    id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    phone      TEXT UNIQUE NOT NULL,
    role       user_role NOT NULL DEFAULT 'user',
    created_at TIMESTAMPTZ DEFAULT timezone('utc', now())
);

-- Ensure these columns exist even if the table was already created earlier
ALTER TABLE profiles 
    ADD COLUMN IF NOT EXISTS full_name TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS email TEXT NOT NULL DEFAULT '';

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select ON profiles;
-- Users can read their own profile
CREATE POLICY profiles_select ON profiles
    FOR SELECT TO authenticated
    USING (auth.uid() = id);

DROP POLICY IF EXISTS profiles_update ON profiles;
-- Users can update their own profile
CREATE POLICY profiles_update ON profiles
    FOR UPDATE TO authenticated
    USING (auth.uid() = id);

DROP POLICY IF EXISTS profiles_insert ON profiles;
-- Users can insert their own profile (during registration)
CREATE POLICY profiles_insert ON profiles
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = id);

-- Create/refresh profile and emergency contacts from auth metadata.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    contact_item jsonb;
    has_emergency_contacts_table boolean;
BEGIN
    INSERT INTO public.profiles (id, phone, role, full_name, email)
    VALUES (
        NEW.id,
        COALESCE(NULLIF(NEW.raw_user_meta_data ->> 'phone', ''), NEW.email, NEW.id::text),
        COALESCE((NEW.raw_user_meta_data ->> 'role')::user_role, 'user'),
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
        COALESCE(NEW.email, '')
    )
    ON CONFLICT (id) DO UPDATE
        SET phone = EXCLUDED.phone,
            role = EXCLUDED.role,
            full_name = EXCLUDED.full_name,
            email = EXCLUDED.email;

    has_emergency_contacts_table := to_regclass('public.emergency_contacts') IS NOT NULL;

    IF has_emergency_contacts_table
       AND jsonb_typeof(NEW.raw_user_meta_data -> 'emergency_contacts') = 'array' THEN
        DELETE FROM public.emergency_contacts
        WHERE user_id = NEW.id;

        FOR contact_item IN
            SELECT value
            FROM jsonb_array_elements(NEW.raw_user_meta_data -> 'emergency_contacts') AS value
        LOOP
            IF COALESCE(contact_item ->> 'label', '') <> ''
               AND COALESCE(contact_item ->> 'phone', '') <> '' THEN
                INSERT INTO public.emergency_contacts (user_id, label, phone)
                VALUES (
                    NEW.id,
                    contact_item ->> 'label',
                    contact_item ->> 'phone'
                );
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ──────────────────────────────────────────────────────────────
-- 3. Emergency Contacts (separate table, not JSONB)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS emergency_contacts (
    id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    label      TEXT NOT NULL DEFAULT '',
    phone      TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_emergency_contacts_user ON emergency_contacts(user_id);

ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS emergency_contacts_select ON emergency_contacts;
CREATE POLICY emergency_contacts_select ON emergency_contacts
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS emergency_contacts_insert ON emergency_contacts;
CREATE POLICY emergency_contacts_insert ON emergency_contacts
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS emergency_contacts_update ON emergency_contacts;
CREATE POLICY emergency_contacts_update ON emergency_contacts
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS emergency_contacts_delete ON emergency_contacts;
CREATE POLICY emergency_contacts_delete ON emergency_contacts
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────
-- 4. SOS Vault (recording metadata)
-- ──────────────────────────────────────────────────────────────
-- Create a storage bucket named 'sos-vault' in the Supabase UI.

CREATE TABLE IF NOT EXISTS sos_vault (
    id                uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id           uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    video_url         TEXT NOT NULL,
    location_snapshot JSONB,
    status            TEXT NOT NULL DEFAULT 'PENDING',
    created_at        TIMESTAMPTZ DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_sos_vault_user ON sos_vault(user_id);

ALTER TABLE sos_vault ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sos_vault_select ON sos_vault;
-- Users can only see their own SOS recordings
CREATE POLICY sos_vault_select ON sos_vault
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS sos_vault_insert ON sos_vault;
CREATE POLICY sos_vault_insert ON sos_vault
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Storage bucket for SOS videos.
INSERT INTO storage.buckets (id, name, public)
VALUES ('sos-vault', 'sos-vault', true)
ON CONFLICT (id) DO UPDATE
    SET name = EXCLUDED.name,
        public = EXCLUDED.public;

DROP POLICY IF EXISTS sos_vault_objects_select ON storage.objects;
CREATE POLICY sos_vault_objects_select ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'sos-vault' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS sos_vault_objects_insert ON storage.objects;
CREATE POLICY sos_vault_objects_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'sos-vault' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS sos_vault_objects_delete ON storage.objects;
CREATE POLICY sos_vault_objects_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'sos-vault' AND (storage.foldername(name))[1] = auth.uid()::text);

-- ──────────────────────────────────────────────────────────────
-- 5. Tracking (live location sharing)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tracking (
    user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    lat        DOUBLE PRECISION NOT NULL,
    lng        DOUBLE PRECISION NOT NULL,
    is_live    BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT timezone('utc', now())
);

ALTER TABLE tracking ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tracking_select ON tracking;
-- Users can read all tracking data (needed for family/friend visibility)
CREATE POLICY tracking_select ON tracking
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS tracking_insert ON tracking;
CREATE POLICY tracking_insert ON tracking
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS tracking_update ON tracking;
CREATE POLICY tracking_update ON tracking
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────
-- 6. Helplines (admin-managed, publicly readable)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS helplines (
    id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name       TEXT NOT NULL,
    number     TEXT NOT NULL,
    category   TEXT DEFAULT 'General',
    created_at TIMESTAMPTZ DEFAULT timezone('utc', now())
);

ALTER TABLE helplines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS helplines_select ON helplines;
-- All authenticated users can read helplines
CREATE POLICY helplines_select ON helplines
    FOR SELECT TO authenticated
    USING (true);

-- ──────────────────────────────────────────────────────────────
-- 7. Safety Content (articles / news, admin-managed)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS safety_content (
    id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    title      TEXT NOT NULL,
    content    TEXT NOT NULL,
    type       TEXT NOT NULL DEFAULT 'ARTICLE',
    image_url  TEXT,
    created_at TIMESTAMPTZ DEFAULT timezone('utc', now())
);

ALTER TABLE safety_content ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS safety_content_select ON safety_content;
-- All authenticated users can read safety content
CREATE POLICY safety_content_select ON safety_content
    FOR SELECT TO authenticated
    USING (true);

-- ──────────────────────────────────────────────────────────────
-- 8. Community Locations (opt-in location sharing)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_locations (
    id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    latitude     DOUBLE PRECISION NOT NULL,
    longitude    DOUBLE PRECISION NOT NULL,
    display_name TEXT DEFAULT 'SafeHer User',
    updated_at   TIMESTAMPTZ DEFAULT timezone('utc', now()),
    CONSTRAINT community_locations_user_unique UNIQUE (user_id)
);

ALTER TABLE community_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS community_locations_select ON community_locations;
CREATE POLICY community_locations_select ON community_locations
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS community_locations_insert ON community_locations;
CREATE POLICY community_locations_insert ON community_locations
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS community_locations_update ON community_locations;
CREATE POLICY community_locations_update ON community_locations
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS community_locations_delete ON community_locations;
CREATE POLICY community_locations_delete ON community_locations
    FOR DELETE TO authenticated USING (auth.uid() = user_id);
