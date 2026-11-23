import { apiRequest } from '../../shared/infrastructure/api-request';

export type Phase = 'executed' | 'today' | 'next' | 'pending';

export interface ScheduleClass {
  id: string;
  class_no: number;
  week_no: number;
  topic_no: number;
  weekday: number;
  title: string;
  description: string;
  duration_minutes: number;
  date: string | null;
  unlock_at: string | null;
  unlocked: boolean;
  executed: boolean;
  manual: 'auto' | 'enabled' | 'blocked';
  phase: Phase;
  completed: boolean;
  completed_at: string | null;
  // Solo llegan cuando la clase está disponible (o para el administrador).
  objectives?: string;
  content?: string;
  activity?: string;
  outcome?: string;
  meet_url?: string | null;
  recording_url?: string | null;
  material_url?: string | null;
  held?: 'auto' | 'held' | 'pending';
}

export interface ScheduleWeek {
  week_no: number;
  title: string;
  objective: string;
  result: string;
  start: string | null;
  end: string | null;
  total: number;
  completed: number;
  topics: { topic_no: number; title: string }[];
  classes: ScheduleClass[];
}

export interface Holiday { day: string; label: string }

export interface SlotInfo { slot_no: number; label: string; starts: string; ends: string; meet_url: string | null }

export interface AdminSlot extends SlotInfo { capacity: number; tier: number; active: boolean; taken: number }

export interface PublicClass {
  class_no: number; topic_no: number; date: string | null; title: string; description: string;
  objectives: string; content: string; activity: string; outcome: string; duration_minutes: number;
}

export interface PublicWeek {
  week_no: number; title: string; objective: string; result: string; start: string | null; end: string | null;
  topics: { topic_no: number; title: string }[]; classes: PublicClass[];
}

export interface PublicSchedule {
  course: { id: string; name: string };
  program: { title: string; tagline: string };
  weeks: PublicWeek[];
  start_date: string | null;
  end_date: string | null;
  classes: { class_no: number; date: string | null }[];
  holidays: Holiday[];
  slots: { slot_no: number; label: string; starts: string; ends: string; capacity: number; remaining: number; full: boolean }[];
}

export interface Schedule {
  course: { id: string; name: string };
  program: { title: string; tagline: string };
  holidays: Holiday[];
  slot: SlotInfo | null;
  slots: AdminSlot[] | null;
  admin: boolean;
  settings: { start_date: string | null; unlock_time: string; timezone: string; program_title: string | null; tagline: string | null };
  total: number;
  completed: number;
  percent: number;
  next: ScheduleClass | null;
  weeks: ScheduleWeek[];
}

export interface StudentProgress {
  student_id: string;
  full_name: string;
  email: string;
  completed: number;
  total: number;
  percent: number;
  last_activity: string | null;
}

export async function loadSchedule(token: string, course?: string): Promise<Schedule | null> {
  try {
    const response = await apiRequest(`/schedule${course ? `?course=${encodeURIComponent(course)}` : ''}`, token);
    return response.ok ? await response.json() as Schedule : null;
  } catch {
    return null;
  }
}

export async function loadPublicSchedule(): Promise<PublicSchedule | null> {
  try {
    const response = await apiRequest('/schedule/public');
    return response.ok ? await response.json() as PublicSchedule : null;
  } catch {
    return null;
  }
}

export async function saveSlot(token: string, slot: number, body: object): Promise<number> {
  try {
    return (await apiRequest(`/admin/schedule/slots/${slot}`, token, body)).status;
  } catch {
    return 503;
  }
}

export async function setHoliday(token: string, body: object): Promise<number> {
  try {
    return (await apiRequest('/admin/schedule/holidays', token, body)).status;
  } catch {
    return 503;
  }
}

export async function setClassDone(token: string, id: string, done: boolean): Promise<boolean> {
  try {
    return (await apiRequest(`/schedule/classes/${encodeURIComponent(id)}/done`, token, { done })).ok;
  } catch {
    return false;
  }
}

export async function saveClass(token: string, id: string, data: Record<string, string>): Promise<number> {
  try {
    return (await apiRequest(`/admin/schedule/classes/${encodeURIComponent(id)}`, token, data)).status;
  } catch {
    return 503;
  }
}

export async function saveSettings(token: string, body: { course: string; startDate: string; unlockTime: string; timezone: string; programTitle?: string; tagline?: string }): Promise<number> {
  try {
    return (await apiRequest('/admin/schedule/settings', token, body)).status;
  } catch {
    return 503;
  }
}

export async function saveWeek(token: string, week: number, body: object): Promise<number> {
  try {
    return (await apiRequest(`/admin/schedule/weeks/${week}`, token, body)).status;
  } catch {
    return 503;
  }
}

export async function loadStudents(token: string, course: string): Promise<StudentProgress[] | null> {
  try {
    const response = await apiRequest(`/admin/schedule/students?course=${encodeURIComponent(course)}`, token);
    return response.ok ? await response.json() as StudentProgress[] : null;
  } catch {
    return null;
  }
}

const day = new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' });
const dayShort = new Intl.DateTimeFormat('es-PE', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' });
const dayMonth = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'short', timeZone: 'UTC' });
export const WEEKDAYS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes'];

/** "2026-01-05" → "lunes, 5 de enero" (la fecha ya viene calculada en la zona del curso). */
export const longDate = (iso: string) => day.format(new Date(`${iso}T12:00:00Z`));
export const shortDate = (iso: string) => dayShort.format(new Date(`${iso}T12:00:00Z`));
export const dayMonthDate = (iso: string) => dayMonth.format(new Date(`${iso}T12:00:00Z`)).replace('.', '');
export const lines = (text?: string) => (text ?? '').split('\n').map((l) => l.trim()).filter(Boolean);

/** "15:00" -> "3:00 p. m." */
export function clock(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number);
  const suffix = h >= 12 ? 'p. m.' : 'a. m.';
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${suffix}`;
}
export const slotRange = (starts: string, ends: string) => `${clock(starts)} – ${clock(ends)}`;

const monthDay = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'short', timeZone: 'UTC' });
/** "2026-12-15", "2026-12-21" -> "15 dic – 21 dic" */
export const rangeLabel = (a: string | null, b: string | null) =>
  a && b ? `${monthDay.format(new Date(`${a}T12:00:00Z`)).replace(/\./g, '')} – ${monthDay.format(new Date(`${b}T12:00:00Z`)).replace(/\./g, '')}` : '';
