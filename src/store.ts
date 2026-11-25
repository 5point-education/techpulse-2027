import { createClient, type Session } from '@supabase/supabase-js';
import { emptyRegistration, makePublicId, type BulkRow, type Registration, type RegistrationInput, type RegistrationStatus, type RegistrationType } from './domain';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;
export const cloudEnabled = Boolean(url && key && !url.includes('YOUR_PROJECT'));
export const supabase = cloudEnabled ? createClient(url!, key!, { auth: { persistSession: true, detectSessionInUrl: true } }) : null;

const REG_KEY = 'tp27_demo_registrations_v2';
const SESSION_KEY = 'tp27_demo_session';
const CLAIM_KEY = 'tp27_demo_claims';

export interface AppUser { id: string; email: string; name: string; role: 'user' | 'admin' | 'checkin'; }

function readLocal(): Registration[] {
  try { return JSON.parse(localStorage.getItem(REG_KEY) || '[]') as Registration[]; } catch { return []; }
}

function writeLocal(records: Registration[]) { localStorage.setItem(REG_KEY, JSON.stringify(records)); }

function mapSession(session: Session | null): AppUser | null {
  if (!session?.user) return null;
  const storedRole = String(session.user.app_metadata.user_role || 'user');
  const role: AppUser['role'] = ['super_admin','registration_staff','event_coordinator'].includes(storedRole) ? 'admin' : storedRole === 'checkin_staff' ? 'checkin' : 'user';
  return { id: session.user.id, email: session.user.email || '', name: String(session.user.user_metadata.full_name || session.user.email?.split('@')[0] || 'Registrant'), role };
}

async function mapSessionWithRole(session: Session | null): Promise<AppUser | null> {
  const user = mapSession(session);
  if (!user || !supabase || user.role !== 'user') return user;
  const { data } = await supabase.from('staff_roles').select('role').eq('user_id', user.id);
  const roles = (data || []).map((item: { role: string }) => item.role);
  if (roles.some((role) => ['super_admin','registration_staff','event_coordinator'].includes(role))) user.role = 'admin';
  else if (roles.includes('checkin_staff')) user.role = 'checkin';
  return user;
}

export async function currentUser(): Promise<AppUser | null> {
  if (supabase) return mapSessionWithRole((await supabase.auth.getSession()).data.session);
  try { return JSON.parse(localStorage.getItem(SESSION_KEY) || 'null') as AppUser | null; } catch { return null; }
}

export async function signUp(email: string, password: string, name: string) {
  if (supabase) {
    const result = await supabase.auth.signUp({ email, password, options: { data: { full_name: name }, emailRedirectTo: `${location.origin}${location.pathname}#dashboard` } });
    if (result.error) throw result.error;
    return { user: mapSession(result.data.session), confirmationRequired: !result.data.session };
  }
  const user: AppUser = { id: `demo-${email.toLowerCase()}`, email, name, role: email.toLowerCase() === 'admin@techpulse.test' ? 'admin' : 'user' };
  localStorage.setItem(SESSION_KEY, JSON.stringify(user));
  return { user, confirmationRequired: false };
}

export async function signIn(email: string, password: string) {
  if (supabase) {
    const result = await supabase.auth.signInWithPassword({ email, password });
    if (result.error) throw result.error;
    return mapSessionWithRole(result.data.session);
  }
  if (!password) throw new Error('Enter your password.');
  const user: AppUser = { id: `demo-${email.toLowerCase()}`, email, name: email.split('@')[0], role: email.toLowerCase() === 'admin@techpulse.test' ? 'admin' : 'user' };
  localStorage.setItem(SESSION_KEY, JSON.stringify(user));
  return user;
}

export async function requestPasswordReset(email: string) {
  if (supabase) {
    const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${location.origin}${location.pathname}#reset-password` });
    if (error) throw error;
  }
}

export async function updatePassword(password: string) {
  if (!supabase) return;
  const { error } = await supabase.auth.updateUser({ password });
  if (error) throw error;
}

export async function signOut() {
  if (supabase) await supabase.auth.signOut();
  localStorage.removeItem(SESSION_KEY);
}

export function onAuthEvent(handler: (event: string) => void) {
  if (!supabase) return () => undefined;
  const { data } = supabase.auth.onAuthStateChange((event) => handler(event));
  return () => data.subscription.unsubscribe();
}

export async function submitRegistration(input: RegistrationInput, user: AppUser, batchRef?: string): Promise<Registration> {
  if (supabase) {
    const { data, error } = await supabase.rpc('submit_registration', { registration: { ...input, batchRef } });
    if (error) throw error;
    return data as Registration;
  }
  const record: Registration = { ...input, id: crypto.randomUUID(), publicId: makePublicId(input.type), ownerId: user.id, status: 'pending', submittedAt: new Date().toISOString(), batchRef };
  writeLocal([...readLocal(), record]);
  return record;
}

export async function submitBulkBatch(rows: BulkRow[], type: RegistrationType, user: AppUser, sourceName = 'uploaded-workbook.xlsx') {
  const institutionName = rows[0]?.institutionName || 'Institution';
  const registrations = rows.map((row) => ({
    ...emptyRegistration(row.type), studentRef: row.studentRef, fullName: row.fullName,
    email: row.email || '', phone: row.phone, institutionType: row.institutionType,
    institutionName: row.institutionName, classYear: row.classYear, city: row.city,
    consent: true, eventCodes: row.eventCodes
  }));
  if (supabase) {
    const { data, error } = await supabase.rpc('submit_bulk_batch', { payload: { type, institutionName, sourceName, registrations } });
    if (error) throw error;
    return data as { batchRef: string; registrations: Registration[] };
  }
  const batchRef = `TP27-B-${Date.now().toString(36).toUpperCase()}`;
  const current = readLocal();
  const records: Registration[] = registrations.map((input) => ({ ...input, id: crypto.randomUUID(), publicId: makePublicId(input.type), ownerId: user.id, status: 'pending', submittedAt: new Date().toISOString(), batchRef }));
  writeLocal([...current, ...records]);
  return { batchRef, registrations: records };
}

export async function listRegistrations(user: AppUser): Promise<Registration[]> {
  if (supabase) {
    const query = supabase.from('registrations').select('*, registration_events(event_code), teams(*)').order('submitted_at', { ascending: false });
    const { data, error } = await query;
    if (error) throw error;
    return (data || []).map((row: any) => ({
      id: row.id, publicId: row.public_id, ownerId: row.owner_id, type: row.registration_type, status: row.status, fullName: row.full_name,
      email: row.email, phone: row.phone, dob: row.dob || '', gender: row.gender || '', category: row.category || '', institutionType: row.institution_type,
      institutionName: row.institution_name || '', classYear: row.class_year || '', city: row.city || '', state: row.state || '', guardianName: row.guardian_name || '',
      guardianPhone: row.guardian_phone || '', consent: row.consent, eventCodes: (row.registration_events || []).map((x: any) => x.event_code), teams: row.teams || [],
      submittedAt: row.submitted_at, reviewedAt: row.reviewed_at, reviewNote: row.review_note, passToken: row.pass_token, batchRef: row.batch_ref
    }));
  }
  const records = readLocal();
  return user.role === 'admin' ? records : records.filter((x) => x.ownerId === user.id);
}

export async function reviewRegistration(id: string, status: Extract<RegistrationStatus, 'approved' | 'rejected' | 'revoked'>, note: string) {
  if (supabase) {
    const { error } = await supabase.rpc('review_registration', { registration_id: id, next_status: status, note });
    if (error) throw error;
    return;
  }
  const records = readLocal().map((item) => item.id === id ? { ...item, status, reviewNote: note, reviewedAt: new Date().toISOString(), passToken: status === 'approved' ? crypto.randomUUID() : undefined } : item);
  writeLocal(records);
}

export async function updateContact(id: string, phone: string, city: string, user: AppUser) {
  if (supabase) {
    const { error } = await supabase.from('registrations').update({ phone, city, updated_at: new Date().toISOString() }).eq('id', id).or(`owner_id.eq.${user.id},claimed_by.eq.${user.id}`);
    if (error) throw error;
    return;
  }
  writeLocal(readLocal().map((x) => x.id === id && x.ownerId === user.id ? { ...x, phone, city } : x));
}

export interface CheckInResult { registrationId: string; name: string; type: RegistrationInput['type']; institution: string; eventDay: string; checkedInAt: string; repeat?: boolean; }
export async function checkInPass(passValue: string, user: AppUser): Promise<CheckInResult> {
  if (supabase) {
    const { data, error } = await supabase.rpc('check_in', { pass_value: passValue.trim() });
    if (error) throw error;
    return data as CheckInResult;
  }
  if (!['admin','checkin'].includes(user.role)) throw new Error('Check-in access required.');
  const record = readLocal().find((item) => item.passToken === passValue.trim() || item.publicId === passValue.trim().toUpperCase());
  if (!record) throw new Error('Pass not found.');
  if (record.status !== 'approved') throw new Error(`Entry denied: registration is ${record.status}.`);
  const eventDay = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
  const key = `tp27_checkin_${record.id}_${eventDay}`;
  const previous = localStorage.getItem(key);
  const checkedInAt = previous || new Date().toISOString();
  if (!previous) localStorage.setItem(key, checkedInAt);
  return { registrationId: record.publicId, name: record.fullName, type: record.type, institution: record.institutionName, eventDay, checkedInAt, repeat: Boolean(previous) };
}

export async function createClaimInvitation(registrationId: string, email: string, user: AppUser) {
  if (supabase) {
    const { data, error } = await supabase.rpc('create_claim_invitation', { registration_id: registrationId, invite_email: email });
    if (error) throw error;
    return String(data);
  }
  const token = crypto.randomUUID();
  const claims = JSON.parse(localStorage.getItem(CLAIM_KEY) || '{}');
  claims[token] = { registrationId, email: email.toLowerCase(), createdBy: user.id };
  localStorage.setItem(CLAIM_KEY, JSON.stringify(claims));
  return token;
}

export async function claimRegistration(token: string, user: AppUser) {
  if (supabase) {
    const { data, error } = await supabase.rpc('claim_registration', { claim_token: token });
    if (error) throw error;
    return String(data);
  }
  const claims = JSON.parse(localStorage.getItem(CLAIM_KEY) || '{}');
  const claim = claims[token];
  if (!claim) throw new Error('This claim invitation is invalid or expired.');
  if (claim.email && claim.email !== user.email.toLowerCase()) throw new Error('Sign in with the email address that received this invitation.');
  writeLocal(readLocal().map((item) => item.id === claim.registrationId ? { ...item, ownerId: user.id } : item));
  delete claims[token]; localStorage.setItem(CLAIM_KEY, JSON.stringify(claims));
  return claim.registrationId as string;
}
