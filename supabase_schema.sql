-- Supabase SQL for SafeHer backend

-- 1. Create enum for user roles
CREATE TYPE user_role AS ENUM ('user', 'admin');

-- 2. Create profiles table
CREATE TABLE profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    phone TEXT UNIQUE NOT NULL,
    role user_role NOT NULL DEFAULT 'user',
    emergency_contacts JSONB NOT NULL, -- Array of {label, phone}
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now())
);

-- 3. Create storage bucket for SOS recordings
-- (This is done via Supabase Storage UI, but for reference:)
-- Create a bucket named 'sos-vault' in Supabase Storage.

-- 4. Policy: Allow users to insert/update their own profile
-- (Set up RLS policies in Supabase dashboard)

-- 5. Policy: Allow only admins to list all SOS recordings
-- (Set up RLS policies for storage access)
