import type { PostgrestSingleResponse } from '@supabase/supabase-js';
import { createAcademyClient } from '../../../platform/supabase/academy-client';
import type { LearningRepository } from '../application/learning';

export class SupabaseLearning implements LearningRepository {
  constructor(private readonly url: string, private readonly key: string) {}

  async program() {
    return unwrap(await createAcademyClient(this.url, this.key).from('academy_program_page').select(
      'title,introduction,description,benefits,duration_text,launch_price,currency,registration_text,registration_url,welcome_drive_file_id',
    ).eq('published', true).maybeSingle());
  }

  async home(token: string) {
    return unwrap(await this.client(token).rpc('academy_campus_home'));
  }

  async course(token: string, id: string) {
    return unwrap(await this.client(token).rpc('academy_course_content', { course: id }));
  }

  async complete(token: string, id: string) {
    return unwrap(await this.client(token).rpc('academy_complete_lesson', { target_lesson: id })) === true;
  }

  async inquiries(token: string, student: string, page: number) {
    const from = (page - 1) * 20;
    const result = await this.client(token).from('academy_inquiries').select(
      'id,subject,body,status,created_at,academy_inquiry_replies(id,body,created_at)', { count: 'exact' },
    ).eq('student_id', student).order('created_at', { ascending: false }).order('id').range(from, from + 19)
      .order('created_at', { referencedTable: 'academy_inquiry_replies', ascending: true });
    return { items: unwrap(result), hasNext: (result.count ?? 0) > from + 20 };
  }

  async createInquiry(token: string, student: string, subject: string, body: string) {
    unwrap(await this.client(token).from('academy_inquiries').insert({ student_id: student, subject, body }));
  }

  private client(accessToken: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}

function unwrap<T>(result: PostgrestSingleResponse<T>): T {
  if (result.error) throw result.error;
  return result.data;
}
