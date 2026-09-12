-- Local Supabase-compatibility shim for independent review (PostgreSQL 16, no Supabase stack available).
create role supabase_admin superuser createdb createrole replication bypassrls login password 'postgres';
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;
create role authenticator noinherit login password 'postgres';
grant anon, authenticated, service_role to authenticator;
create role supabase_auth_admin noinherit createrole login password 'postgres';
create role supabase_storage_admin noinherit createrole login password 'postgres';
create role dashboard_user nologin;
-- schemas
create schema extensions;
grant usage on schema extensions to postgres, anon, authenticated, service_role;
alter default privileges in schema extensions grant execute on functions to postgres, anon, authenticated, service_role;
create schema vault;
create schema graphql_public;
grant usage on schema graphql_public to postgres, anon, authenticated, service_role;
-- public grants and Supabase default privileges (the "factory" that A5.1a later locks)
grant usage on schema public to postgres, anon, authenticated, service_role;
-- (v2) no postgres-grantor default grants: CI evidence (probe_defpriv passes on the unmodified baseline helper _e10_inv_bad_num) shows postgres-created objects do not receive explicit anon/authenticated grants in the Supabase stack; only the supabase_admin-grantor defaults exist.
alter default privileges for role supabase_admin in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public grant all on sequences to postgres, anon, authenticated, service_role;
-- auth
create schema auth authorization supabase_auth_admin;
grant usage on schema auth to postgres, anon, authenticated, service_role;
create table auth.users (
  instance_id uuid, id uuid primary key, aud varchar(255), role varchar(255), email varchar(255),
  encrypted_password varchar(255), email_confirmed_at timestamptz, invited_at timestamptz,
  confirmation_token varchar(255), confirmation_sent_at timestamptz, recovery_token varchar(255),
  recovery_sent_at timestamptz, email_change_token_new varchar(255), email_change varchar(255),
  email_change_sent_at timestamptz, last_sign_in_at timestamptz, raw_app_meta_data jsonb, raw_user_meta_data jsonb,
  is_super_admin boolean, created_at timestamptz, updated_at timestamptz, phone text unique, phone_confirmed_at timestamptz,
  phone_change text default '', phone_change_token varchar(255) default '', phone_change_sent_at timestamptz,
  confirmed_at timestamptz generated always as (least(email_confirmed_at, phone_confirmed_at)) stored,
  email_change_token_current varchar(255) default '', email_change_confirm_status smallint default 0,
  banned_until timestamptz, reauthentication_token varchar(255) default '', reauthentication_sent_at timestamptz,
  is_sso_user boolean not null default false, deleted_at timestamptz, is_anonymous boolean not null default false
);
alter table auth.users owner to supabase_auth_admin;
create unique index users_email_partial_key on auth.users(email) where is_sso_user = false;
grant all on auth.users to postgres, supabase_auth_admin;
grant select on auth.users to service_role;
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create or replace function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))::text $$;
create or replace function auth.email() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.email', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email'))::text $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''),
                  nullif(current_setting('request.jwt.claims', true), ''))::jsonb $$;
alter function auth.uid() owner to supabase_auth_admin; alter function auth.role() owner to supabase_auth_admin;
alter function auth.email() owner to supabase_auth_admin; alter function auth.jwt() owner to supabase_auth_admin;
grant execute on function auth.uid(), auth.role(), auth.email(), auth.jwt() to public;
-- storage
create schema storage authorization supabase_storage_admin;
grant usage on schema storage to postgres, anon, authenticated, service_role;
create table storage.buckets (id text primary key, name text not null unique, owner uuid, created_at timestamptz default now(), updated_at timestamptz default now(), public boolean default false, avif_autodetection boolean default false, file_size_limit bigint, allowed_mime_types text[], owner_id text);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text, owner uuid, created_at timestamptz default now(), updated_at timestamptz default now(), last_accessed_at timestamptz default now(), metadata jsonb, path_tokens text[] generated always as (string_to_array(name, '/')) stored, version text, owner_id text, user_metadata jsonb);
alter table storage.buckets owner to supabase_storage_admin; alter table storage.objects owner to supabase_storage_admin;
alter table storage.objects enable row level security; alter table storage.buckets enable row level security;
grant all on storage.buckets, storage.objects to postgres, supabase_storage_admin, service_role;
grant select, insert, update, delete on storage.objects to anon, authenticated;
grant select on storage.buckets to anon, authenticated;
create or replace function storage.foldername(name text) returns text[] language plpgsql immutable as $$ declare _parts text[]; begin select string_to_array(name, '/') into _parts; return _parts[1:array_length(_parts,1)-1]; end $$;
create or replace function storage.filename(name text) returns text language plpgsql immutable as $$ declare _parts text[]; begin select string_to_array(name, '/') into _parts; return _parts[array_length(_parts,1)]; end $$;
create or replace function storage.extension(name text) returns text language plpgsql immutable as $$ declare _parts text[]; _filename text; begin select string_to_array(name, '/') into _parts; select _parts[array_length(_parts,1)] into _filename; return reverse(split_part(reverse(_filename), '.', 1)); end $$;
-- realtime publication + migration ledger
create publication supabase_realtime;
create schema supabase_migrations;
create table supabase_migrations.schema_migrations (version text primary key, statements text[], name text);
-- Supabase sets the database/role search_path to include extensions
alter database postgres set search_path to "$user", public, extensions;
alter role postgres set search_path to "$user", public, extensions;
alter role authenticator set search_path to "$user", public, extensions;
