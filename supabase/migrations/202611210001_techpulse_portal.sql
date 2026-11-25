-- TECHPULSE 2027 portal schema. Apply to the dedicated, empty Supabase project.
create extension if not exists pgcrypto;

create type public.registration_type as enum ('visitor','participant');
create type public.institution_type as enum ('school','college','other','pass_out');
create type public.registration_status as enum ('draft','pending','approved','rejected','revoked');
create type public.staff_role as enum ('super_admin','registration_staff','event_coordinator','checkin_staff');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  created_at timestamptz not null default now()
);

create table public.staff_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.staff_role not null,
  event_codes text[] not null default '{}',
  primary key (user_id, role)
);

create table public.events (
  code text primary key,
  name text not null,
  subtitle text not null,
  description text not null,
  active boolean not null default true,
  rules jsonb not null default '{}',
  display_order integer not null default 0
);

insert into public.events(code,name,subtitle,description,display_order) values
('ROBO_RACE','Robo Race','Nitro Circuit','Speed and obstacle circuit.',1),
('ROBO_SOCCER','Robo Soccer','Goalbyte Arena','Robot football challenge.',2),
('ROBO_SUMO','Robo Sumo','Mech Mayhem','Robot pushing contest.',3),
('LINE_FOLLOWER','Line Follower','Autonomy Run','Autonomous navigation challenge.',4),
('WATER_ROCKET','Water Rocket','Altitude Challenge','Pressurised rocket engineering.',5);

create sequence public.registration_number start 1001;
create sequence public.batch_number start 101;

create table public.registration_batches (
  id uuid primary key default gen_random_uuid(),
  batch_ref text not null unique default ('TP27-B-' || lpad(nextval('public.batch_number')::text,5,'0')),
  owner_id uuid not null references auth.users(id) on delete cascade,
  registration_type public.registration_type not null,
  institution_name text not null,
  source_name text,
  row_count integer not null check (row_count between 1 and 500),
  created_at timestamptz not null default now()
);

create table public.registrations (
  id uuid primary key default gen_random_uuid(),
  public_id text not null unique,
  owner_id uuid not null references auth.users(id) on delete cascade,
  claimed_by uuid references auth.users(id) on delete set null,
  batch_id uuid references public.registration_batches(id) on delete set null,
  batch_ref text,
  student_ref text,
  registration_type public.registration_type not null,
  status public.registration_status not null default 'pending',
  full_name text not null check (char_length(trim(full_name)) >= 2),
  email text not null default '',
  phone text not null,
  dob date,
  gender text not null default '',
  category text not null default '',
  institution_type public.institution_type not null,
  institution_name text not null default '',
  class_year text not null,
  city text not null,
  state text not null default 'West Bengal',
  guardian_name text not null default '',
  guardian_phone text not null default '',
  consent boolean not null check (consent),
  pass_token uuid,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  review_note text not null default '',
  updated_at timestamptz not null default now(),
  unique(batch_id, student_ref)
);

create table public.registration_events (
  registration_id uuid not null references public.registrations(id) on delete cascade,
  event_code text not null references public.events(code),
  primary key(registration_id,event_code)
);

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.registrations(id) on delete cascade,
  event_code text not null references public.events(code),
  team_name text not null default '',
  member_names text[] not null default '{}',
  unique(registration_id,event_code)
);

create table public.claim_invitations (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.registrations(id) on delete cascade,
  email text not null,
  token_hash text not null unique,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.checkins (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.registrations(id) on delete cascade,
  event_day date not null check (event_day in (date '2027-10-17',date '2027-10-18')),
  checked_in_at timestamptz not null default now(),
  checked_in_by uuid not null references auth.users(id),
  unique(registration_id,event_day)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table public.portal_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.portal_settings(key,value) values
('event', '{"name":"TECHPULSE 2027","startDate":"2027-10-17","endDate":"2027-10-18","timezone":"Asia/Kolkata","venue":"Grand Tech Arena & Convention, Sonarpur"}'),
('registration', '{"approvedContactEditCutoff":"2027-10-15T23:59:59+05:30","maxBulkRows":500,"maxUploadBytes":10485760}');

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),coalesce(new.email,'')); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.is_staff(allowed public.staff_role[] default null) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.staff_roles s where s.user_id=auth.uid() and (allowed is null or s.role=any(allowed)))
$$;

create or replace function public.next_public_id(kind public.registration_type) returns text language plpgsql security definer set search_path=public as $$
begin return 'TP27-' || case when kind='visitor' then 'V' else 'P' end || '-' || lpad(nextval('public.registration_number')::text,6,'0'); end $$;

create or replace function public.submit_registration(registration jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.registrations; ev text; tm jsonb; kind public.registration_type := (registration->>'type')::public.registration_type;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce((registration->>'consent')::boolean,false) is false then raise exception 'Consent is required'; end if;
  if kind='participant' and jsonb_array_length(coalesce(registration->'eventCodes','[]'))=0 then raise exception 'Select at least one event'; end if;
  insert into public.registrations(public_id,owner_id,batch_ref,registration_type,full_name,email,phone,dob,gender,category,institution_type,institution_name,class_year,city,state,guardian_name,guardian_phone,consent)
  values(public.next_public_id(kind),auth.uid(),nullif(registration->>'batchRef',''),kind,trim(registration->>'fullName'),lower(trim(coalesce(registration->>'email',''))),trim(registration->>'phone'),nullif(registration->>'dob','')::date,coalesce(registration->>'gender',''),coalesce(registration->>'category',''),(registration->>'institutionType')::public.institution_type,coalesce(registration->>'institutionName',''),registration->>'classYear',registration->>'city',coalesce(registration->>'state','West Bengal'),coalesce(registration->>'guardianName',''),coalesce(registration->>'guardianPhone',''),true) returning * into r;
  for ev in select jsonb_array_elements_text(coalesce(registration->'eventCodes','[]')) loop insert into public.registration_events values(r.id,ev); end loop;
  for tm in select * from jsonb_array_elements(coalesce(registration->'teams','[]')) loop insert into public.teams(registration_id,event_code,team_name,member_names) values(r.id,tm->>'eventCode',coalesce(tm->>'teamName',''),array(select jsonb_array_elements_text(coalesce(tm->'members','[]')))); end loop;
  insert into public.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'registration.submitted','registration',r.id);
  return jsonb_build_object('id',r.id,'publicId',r.public_id,'ownerId',r.owner_id,'type',r.registration_type,'status',r.status,'fullName',r.full_name,'email',r.email,'phone',r.phone,'dob',r.dob,'gender',r.gender,'category',r.category,'institutionType',r.institution_type,'institutionName',r.institution_name,'classYear',r.class_year,'city',r.city,'state',r.state,'guardianName',r.guardian_name,'guardianPhone',r.guardian_phone,'consent',r.consent,'eventCodes',coalesce(registration->'eventCodes','[]'),'teams',coalesce(registration->'teams','[]'),'submittedAt',r.submitted_at,'batchRef',r.batch_ref);
end $$;

create or replace function public.submit_bulk_batch(payload jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.registration_batches; item jsonb; ids jsonb := '[]'; result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if jsonb_array_length(payload->'registrations') not between 1 and 500 then raise exception 'Batch must contain 1 to 500 rows'; end if;
  insert into public.registration_batches(owner_id,registration_type,institution_name,source_name,row_count)
  values(auth.uid(),(payload->>'type')::public.registration_type,payload->>'institutionName',payload->>'sourceName',jsonb_array_length(payload->'registrations')) returning * into b;
  for item in select * from jsonb_array_elements(payload->'registrations') loop
    result := public.submit_registration(item || jsonb_build_object('batchRef',b.batch_ref));
    update public.registrations set batch_id=b.id,student_ref=item->>'studentRef' where id=(result->>'id')::uuid;
    ids := ids || jsonb_build_array(result);
  end loop;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'batch.submitted','batch',b.id,jsonb_build_object('rows',b.row_count));
  return jsonb_build_object('batchRef',b.batch_ref,'registrations',ids);
end $$;

create or replace function public.review_registration(registration_id uuid,next_status public.registration_status,note text default '') returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff(array['super_admin','registration_staff']::public.staff_role[]) then raise exception 'Staff access required'; end if;
  if next_status not in ('approved','rejected','revoked') then raise exception 'Invalid review status'; end if;
  update public.registrations set status=next_status,review_note=coalesce(note,''),reviewed_at=now(),reviewed_by=auth.uid(),pass_token=case when next_status='approved' then coalesce(pass_token,gen_random_uuid()) else pass_token end,updated_at=now() where id=registration_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'registration.'||next_status,'registration',registration_id,jsonb_build_object('note',note));
end $$;

create or replace function public.check_in(pass_value text) returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.registrations; d date := (now() at time zone 'Asia/Kolkata')::date; c public.checkins;
begin
  if not public.is_staff(array['super_admin','checkin_staff']::public.staff_role[]) then raise exception 'Check-in access required'; end if;
  select * into r from public.registrations where pass_token::text=pass_value or public_id=upper(pass_value);
  if r.id is null then raise exception 'Pass not found'; end if;
  if r.status<>'approved' then raise exception 'Pass is not active'; end if;
  if d not in (date '2027-10-17',date '2027-10-18') then raise exception 'Check-in is outside the festival dates'; end if;
  insert into public.checkins(registration_id,event_day,checked_in_by) values(r.id,d,auth.uid()) on conflict(registration_id,event_day) do update set registration_id=excluded.registration_id returning * into c;
  return jsonb_build_object('registrationId',r.public_id,'name',r.full_name,'type',r.registration_type,'institution',r.institution_name,'eventDay',c.event_day,'checkedInAt',c.checked_in_at);
end $$;

create or replace function public.create_claim_invitation(registration_id uuid,invite_email text) returns text language plpgsql security definer set search_path=public as $$
declare token text := gen_random_uuid()::text; owner uuid;
begin
  select owner_id into owner from public.registrations where id=registration_id;
  if owner is null or (owner<>auth.uid() and not public.is_staff()) then raise exception 'Registration access required'; end if;
  delete from public.claim_invitations ci where ci.registration_id=$1 and ci.claimed_at is null;
  insert into public.claim_invitations(registration_id,email,token_hash,expires_at,created_by)
  values(registration_id,lower(trim(invite_email)),encode(digest(token,'sha256'),'hex'),now()+interval '14 days',auth.uid());
  insert into public.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'claim.created','registration',registration_id);
  return token;
end $$;

create or replace function public.claim_registration(claim_token text) returns uuid language plpgsql security definer set search_path=public as $$
declare invite public.claim_invitations; account_email text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into invite from public.claim_invitations where token_hash=encode(digest(claim_token,'sha256'),'hex') and claimed_at is null and expires_at>now() for update;
  if invite.id is null then raise exception 'Invitation is invalid or expired'; end if;
  if account_email<>invite.email then raise exception 'Sign in with the invited email address'; end if;
  update public.registrations set claimed_by=auth.uid(),updated_at=now() where id=invite.registration_id;
  update public.claim_invitations set claimed_at=now() where id=invite.id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'claim.completed','registration',invite.registration_id);
  return invite.registration_id;
end $$;

alter table public.profiles enable row level security; alter table public.staff_roles enable row level security; alter table public.events enable row level security;
alter table public.registration_batches enable row level security; alter table public.registrations enable row level security; alter table public.registration_events enable row level security;
alter table public.teams enable row level security; alter table public.claim_invitations enable row level security; alter table public.checkins enable row level security;
alter table public.audit_log enable row level security; alter table public.portal_settings enable row level security;

create policy "profiles own read" on public.profiles for select to authenticated using(id=auth.uid() or public.is_staff());
create policy "profiles own update" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy "events public read" on public.events for select using(active or public.is_staff());
create policy "settings public read" on public.portal_settings for select using(true);
create policy "roles own read" on public.staff_roles for select to authenticated using(user_id=auth.uid() or public.is_staff(array['super_admin']::public.staff_role[]));
create policy "registrations owner/staff read" on public.registrations for select to authenticated using(owner_id=auth.uid() or claimed_by=auth.uid() or public.is_staff());
create policy "registrations contact update" on public.registrations for update to authenticated using(owner_id=auth.uid() or claimed_by=auth.uid()) with check(owner_id=auth.uid() or claimed_by=auth.uid());
create policy "registration events visible with parent" on public.registration_events for select to authenticated using(exists(select 1 from public.registrations r where r.id=registration_id and (r.owner_id=auth.uid() or r.claimed_by=auth.uid() or public.is_staff())));
create policy "teams visible with parent" on public.teams for select to authenticated using(exists(select 1 from public.registrations r where r.id=registration_id and (r.owner_id=auth.uid() or r.claimed_by=auth.uid() or public.is_staff())));
create policy "batches owner/staff read" on public.registration_batches for select to authenticated using(owner_id=auth.uid() or public.is_staff());
create policy "invites owner/staff read" on public.claim_invitations for select to authenticated using(created_by=auth.uid() or public.is_staff());
create policy "checkins staff only" on public.checkins for select to authenticated using(public.is_staff());
create policy "audit staff only" on public.audit_log for select to authenticated using(public.is_staff(array['super_admin','registration_staff']::public.staff_role[]));

revoke all on all tables in schema public from anon;
grant select on public.events,public.portal_settings to anon;
grant select,update on public.profiles to authenticated;
grant select on public.registrations to authenticated;
grant update(phone,city,updated_at) on public.registrations to authenticated;
grant select on public.events,public.portal_settings,public.staff_roles,public.registration_batches,public.registration_events,public.teams,public.claim_invitations,public.checkins,public.audit_log to authenticated;
grant execute on function public.submit_registration(jsonb),public.submit_bulk_batch(jsonb),public.review_registration(uuid,public.registration_status,text),public.check_in(text),public.create_claim_invitation(uuid,text),public.claim_registration(text) to authenticated;

-- Bootstrap the first administrator after that person signs up:
-- insert into public.staff_roles(user_id,role) select id,'super_admin' from auth.users where email='YOUR_ADMIN_EMAIL';
