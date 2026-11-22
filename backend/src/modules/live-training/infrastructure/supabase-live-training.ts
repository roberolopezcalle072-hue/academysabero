import type { PostgrestSingleResponse } from '@supabase/supabase-js';
import { createAcademyClient } from '../../../platform/supabase/academy-client';
import type { AttendanceStatus, LiveTrainingRepository, SessionDetails } from '../application/live-training';

const sessionFields = 'id,course_id,title,program_day,description,starts_at,ends_at,meet_url,status,academy_courses!inner(name)';
const recoveryFields = ',academy_session_recovery(recording_url,recording_file_id,material_url,material_file_id)';

export class SupabaseLiveTraining implements LiveTrainingRepository {
  constructor(private readonly url: string, private readonly key: string) {}

  async agenda(token: string, page: number) {
    const client = this.client(token);
    const now = new Date().toISOString();
    const from = (page - 1) * 20;
    const [upcoming, past] = await Promise.all([
      client.from('academy_live_sessions').select(sessionFields)
        .eq('status', 'scheduled').gt('ends_at', now).order('starts_at').order('id').limit(30),
      client.from('academy_live_sessions').select(
        'id,course_id,title,program_day,description,starts_at,ends_at,status,academy_courses!inner(name)' + recoveryFields,
        { count: 'exact' },
      ).in('status', ['scheduled', 'completed']).lte('ends_at', now)
        .order('starts_at', { ascending: false }).order('id').range(from, from + 19),
    ]);
    return { upcoming: unwrap(upcoming), past: unwrap(past), hasNext: (past.count ?? 0) > from + 20 };
  }

  async administration(token: string, page: number, session?: string) {
    const client = this.client(token);
    const from = (page - 1) * 20;
    const [courses, sessions, selected] = await Promise.all([
      client.from('academy_courses').select('id,name').order('name').order('id'),
      client.from('academy_live_sessions').select(sessionFields, { count: 'exact' })
        .order('starts_at', { ascending: false }).order('id').range(from, from + 19),
      session && client.from('academy_live_sessions').select(sessionFields + recoveryFields).eq('id', session).maybeSingle(),
    ]);
    return {
      courses: unwrap(courses), sessions: unwrap(sessions),
      selected: selected ? unwrap(selected) : null, hasNext: (sessions.count ?? 0) > from + 20,
    };
  }

  async roster(token: string, session: string, page: number, presentOnly: boolean) {
    const { data, error } = await this.client(token).rpc('academy_session_roster', {
      p_session: session, p_present_only: presentOnly, p_offset: (page - 1) * 25,
    });
    if (error) throw error;
    if (!Array.isArray(data)) throw new Error('Invalid attendance result');
    return { items: data.slice(0, 25), hasNext: data.length > 25 };
  }

  async save(token: string, session: string | null, details: SessionDetails) {
    const { data, error } = await this.client(token).rpc('academy_save_live_session', {
      p_session: session, p_course: details.course, p_title: details.title, p_day: details.day,
      p_description: details.description, p_starts: details.starts, p_ends: details.ends,
      p_meet: details.meet, p_status: details.status, p_recording: details.recording, p_material: details.material,
    });
    if (error) throw error;
    return typeof data === 'string' ? data : null;
  }

  async cancel(token: string, session: string) {
    const result = await this.client(token).from('academy_live_sessions').update({ status: 'cancelled' })
      .eq('id', session).in('status', ['draft', 'scheduled', 'cancelled']).select('id').maybeSingle();
    return Boolean(unwrap(result));
  }

  async recordAttendance(token: string, session: string, student: string, status: AttendanceStatus) {
    const { data, error } = await this.client(token).rpc('academy_save_attendance', {
      p_session: session, p_student: student, p_status: status,
    });
    if (error) throw error;
    return data === true;
  }

  private client(accessToken: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}

function unwrap<T>(result: PostgrestSingleResponse<T>): T {
  if (result.error) throw result.error;
  return result.data;
}
