import { createAcademyClient } from '../../../platform/supabase/academy-client';

export interface AdminInquiry {
  id: string;
  subject: string;
  body: string;
  status: 'open' | 'answered' | 'closed';
  created_at: string;
  student_name: string;
  student_email: string;
  replies: { id: string; body: string; created_at: string }[];
}

/** Consultas de los alumnos vistas por el administrador (la base de datos valida que lo sea). */
export class SupabaseInquiries {
  constructor(private readonly url: string, private readonly key: string) {}

  async list(token: string, status: string, page: number): Promise<{ hasNext: boolean; items: AdminInquiry[] }> {
    const { data, error } = await this.client(token).rpc('academy_admin_inquiries', { p_status: status, p_page: page });
    if (error) throw error;
    return data;
  }

  /** Guarda la respuesta y devuelve los datos para avisar al alumno por correo. */
  async reply(token: string, id: string, body: string): Promise<{ student_name: string; student_email: string; subject: string }> {
    const { data, error } = await this.client(token).rpc('academy_admin_reply_inquiry', { p_id: id, p_body: body });
    if (error) throw error;
    const row = Array.isArray(data) ? data[0] : data;
    if (!row) throw new Error('Reply was not saved');
    return row;
  }

  private client(accessToken: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}
