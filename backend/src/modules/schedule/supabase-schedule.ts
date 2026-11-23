import { createAcademyClient } from '../../platform/supabase/academy-client';

/** Todo el cronograma pasa por funciones de la base de datos: ahí se decide qué puede ver cada persona. */
export class SupabaseSchedule {
  constructor(private readonly url: string, private readonly key: string) {}

  async load(token: string, course?: string): Promise<unknown> {
    const { data, error } = await this.client(token).rpc('academy_schedule', { p_course: course ?? null });
    if (error) throw error;
    return data;
  }

  /** Fechas, feriados y turnos disponibles (sin contenido ni enlaces): pública. */
  async publicSchedule(): Promise<unknown> {
    const { data, error } = await createAcademyClient(this.url, this.key).rpc('academy_public_schedule', { p_course: null });
    if (error) throw error;
    return data;
  }

  async saveSlot(token: string, course: string, slot: number, v: {
    label: string; starts: string; ends: string; meet: string; capacity: number; tier: number; active: boolean;
  }) {
    const { error } = await this.client(token).rpc('academy_admin_save_slot', {
      p_course: course, p_slot: slot, p_label: v.label, p_starts: v.starts, p_ends: v.ends, p_meet: v.meet,
      p_capacity: v.capacity, p_tier: v.tier, p_active: v.active,
    });
    if (error) throw error;
  }

  async setHoliday(token: string, course: string, day: string, label: string, remove: boolean) {
    const { error } = await this.client(token).rpc('academy_admin_set_holiday', {
      p_course: course, p_day: day, p_label: label, p_remove: remove,
    });
    if (error) throw error;
  }

  async setDone(token: string, classId: string, done: boolean) {
    const { error } = await this.client(token).rpc('academy_set_class_done', { p_class: classId, p_done: done });
    if (error) throw error;
  }

  async saveClass(token: string, id: string, data: Record<string, string>) {
    const { error } = await this.client(token).rpc('academy_admin_save_class', { p_id: id, p_data: data });
    if (error) throw error;
  }

  async saveSettings(token: string, course: string, start: string | null, time: string, timezone: string) {
    const { error } = await this.client(token).rpc('academy_admin_save_settings', {
      p_course: course, p_start: start, p_time: time, p_timezone: timezone,
    });
    if (error) throw error;
  }

  async saveWeek(token: string, course: string, week: number, title: string, objective: string,
                 topics: { topic_no: number; title: string }[]) {
    const { error } = await this.client(token).rpc('academy_admin_save_week', {
      p_course: course, p_week: week, p_title: title, p_objective: objective, p_topics: topics,
    });
    if (error) throw error;
  }

  async students(token: string, course: string): Promise<unknown> {
    const { data, error } = await this.client(token).rpc('academy_admin_schedule_students', { p_course: course });
    if (error) throw error;
    return data;
  }

  private client(token: string) {
    return createAcademyClient(this.url, this.key, token);
  }
}
