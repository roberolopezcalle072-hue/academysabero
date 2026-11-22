import { createAcademyClient } from '../../../platform/supabase/academy-client';
import type { AccessAdministration } from '../application/manage-access';

export class SupabaseAdministration implements AccessAdministration {
  constructor(private readonly url: string, private readonly key: string) {}

  async list(token: string, page: number) {
    const client = this.client(token);
    const from = (page - 1) * 25;
    const to = from + 24;
    const [students, emails, courses, assignments] = await Promise.all([
      client.from('academy_student_profiles').select('user_id,full_name,google_email,access_active', { count: 'exact' }).order('google_email').range(from, to),
      client.from('academy_authorized_emails').select('email,active', { count: 'exact' }).order('email').range(from, to),
      client.from('academy_courses').select('id,name', { count: 'exact' }).order('name').order('id').range(from, to),
      client.from('academy_email_enrollments').select('email,course_id,claimed_at', { count: 'exact' }).order('email').order('course_id').range(from, to),
    ]);
    for (const result of [students, emails, courses, assignments]) {
      if (result.error) throw result.error;
    }
    return {
      students: students.data, emails: emails.data, courses: courses.data, assignments: assignments.data,
      hasNext: [students, emails, courses, assignments].some(result => (result.count ?? 0) > to + 1),
    };
  }

  async setEmail(token: string, email: string, active: boolean) {
    const { error } = await this.client(token).from('academy_authorized_emails').upsert({ email, active });
    if (error) throw error;
  }

  async assign(token: string, email: string, course: string, digest: string | null) {
    const { error } = await this.client(token).rpc('academy_assign_email_enrollment', {
      p_email: email, p_course: course, p_digest: digest,
    });
    if (error) throw error;
  }

  async students(token: string, query: string, page: number) {
    const from = (page - 1) * 25;
    const to = from + 24;
    let request = this.client(token)
      .from('academy_student_profiles')
      .select('user_id,full_name,google_email,access_active,registered_at', { count: 'exact' })
      .order('registered_at', { ascending: false })
      .range(from, to);
    // El texto se limpia para que no pueda alterar el filtro de PostgREST.
    const term = query.replace(/[^\p{L}\p{N}@._+\- ]/gu, '').trim().slice(0, 80);
    if (term) request = request.or(`google_email.ilike.%${term}%,full_name.ilike.%${term}%`);
    const { data, error, count } = await request;
    if (error) throw error;
    return { students: data, hasNext: (count ?? 0) > to + 1 };
  }

  async setPassword(token: string, student: string, password: string) {
    const { error } = await this.client(token).rpc('academy_admin_set_password', {
      p_student: student, p_password: password,
    });
    if (error) throw error;
  }

  private client(accessToken: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}
