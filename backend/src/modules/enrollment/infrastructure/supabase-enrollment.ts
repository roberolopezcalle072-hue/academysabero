import { createAcademyClient } from '../../../platform/supabase/academy-client';

export interface CatalogCourse {
  id: string;
  name: string;
  description: string;
  image_path: string;
  price_regular: number;
  price_offer: number;
  currency: string;
  enrolled: boolean;
  request_status: 'pending' | 'approved' | 'rejected' | null;
}

export interface EnrollmentInput {
  courseId: string;
  fullName: string;
  phone: string;
  country: string;
  notes: string | null;
  termsVersion: string;
}

export class SupabaseEnrollment {
  constructor(private readonly url: string, private readonly key: string) {}

  async catalog(token: string): Promise<CatalogCourse[]> {
    const { data, error } = await this.client(token).rpc('academy_catalog');
    if (error) throw error;
    return (data ?? []).map((row: CatalogCourse) => ({
      ...row,
      price_regular: Number(row.price_regular),
      price_offer: Number(row.price_offer),
    }));
  }

  async request(token: string, input: EnrollmentInput): Promise<string> {
    const { data, error } = await this.client(token).rpc('academy_request_enrollment', {
      p_course: input.courseId,
      p_name: input.fullName,
      p_phone: input.phone,
      p_country: input.country,
      p_notes: input.notes,
      p_terms_version: input.termsVersion,
    });
    if (error) throw error;
    return String(data);
  }

  async mine(token: string) {
    const { data, error } = await this.client(token)
      .from('academy_enrollment_requests')
      .select('id,course_id,status,price_offer,currency,created_at,review_note')
      .order('created_at', { ascending: false })
      .limit(50);
    if (error) throw error;
    return data;
  }

  async pending(token: string, status: string, page: number) {
    const from = (page - 1) * 25;
    const to = from + 24;
    let query = this.client(token)
      .from('academy_enrollment_requests')
      .select(
        'id,full_name,email,phone,country,notes,price_regular,price_offer,currency,terms_version,terms_accepted_at,status,review_note,created_at,reviewed_at,academy_courses(name)',
        { count: 'exact' },
      )
      .order('created_at', { ascending: false })
      .range(from, to);
    if (status !== 'all') query = query.eq('status', status);
    const { data, error, count } = await query;
    if (error) throw error;
    return { requests: data, hasNext: (count ?? 0) > to + 1 };
  }

  async review(token: string, id: string, approve: boolean, note: string | null) {
    const { error } = await this.client(token).rpc('academy_review_enrollment_request', {
      p_id: id, p_approve: approve, p_note: note,
    });
    if (error) throw error;
  }

  private client(accessToken: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}
