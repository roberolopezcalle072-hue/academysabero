import { createAcademyClient } from '../../platform/supabase/academy-client';

export interface ComplaintInput {
  kind: 'reclamo' | 'queja';
  fullName: string;
  docType: string;
  docNumber: string;
  address: string;
  phone: string;
  email: string;
  isMinor: boolean;
  guardian: string | null;
  service: string;
  amount: string | null;
  detail: string;
  request: string;
}

export class SupabaseComplaints {
  constructor(private readonly url: string, private readonly key: string) {}

  async submit(input: ComplaintInput): Promise<string> {
    const { data, error } = await this.client().rpc('academy_submit_complaint', {
      p_kind: input.kind, p_name: input.fullName, p_doc_type: input.docType, p_doc_number: input.docNumber,
      p_address: input.address, p_phone: input.phone, p_email: input.email, p_is_minor: input.isMinor,
      p_guardian: input.guardian, p_service: input.service, p_amount: input.amount,
      p_detail: input.detail, p_request: input.request,
    });
    if (error) throw error;
    return String(data);
  }

  async list(token: string, status: string, page: number) {
    const from = (page - 1) * 25;
    const to = from + 24;
    let query = this.client(token)
      .from('academy_complaints')
      .select('id,code,kind,full_name,doc_type,doc_number,address,phone,email,is_minor,guardian_name,service,amount_claimed,detail,request,status,response,answered_at,created_at', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);
    if (status !== 'all') query = query.eq('status', status);
    const { data, error, count } = await query;
    if (error) throw error;
    return { complaints: data, hasNext: (count ?? 0) > to + 1 };
  }

  async answer(token: string, id: string, response: string) {
    const { error } = await this.client(token).rpc('academy_answer_complaint', { p_id: id, p_response: response });
    if (error) throw error;
  }

  private client(accessToken?: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}
