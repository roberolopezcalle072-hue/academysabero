export interface Program {
  title: string;
  introduction: string;
  description: string;
  benefits: string[];
  duration_text: string;
  launch_price: number | null;
  currency: string | null;
  registration_text: string;
  registration_url: string;
  welcome_drive_file_id: string | null;
}

export interface CourseSummary {
  id: string;
  name: string;
  description: string;
  image_path: string;
  duration_minutes: number;
}

export interface Campus {
  name: string | null;
  courses: (CourseSummary & { progress: number })[];
  next_session: { title: string; course: string; starts_at: string; ends_at: string; meet_url: string } | null;
  pending: { id: string; course_id: string; title: string; day_number: number; course: string }[];
}

export interface Lesson {
  id: string;
  title: string;
  day_number: number;
  objective: string | null;
  description: string;
  prompt: string | null;
  instructions: string | null;
  deliverable: string | null;
  validation_criteria: string | null;
  completed: boolean;
  materials: { id: string; title: string; kind: string; drive_url: string; drive_file_id: string | null }[];
}

export interface Course extends CourseSummary {
  modules: { id: string; title: string; lessons: Lesson[] }[];
}

export interface InquiryPage {
  items: {
    id: string;
    subject: string;
    body: string;
    status: 'open' | 'answered' | 'closed';
    created_at: string;
    academy_inquiry_replies: { id: string; body: string; created_at: string }[];
  }[];
  hasNext: boolean;
}
