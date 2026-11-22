export type SessionStatus = 'draft' | 'scheduled' | 'completed' | 'cancelled';
export type AttendanceStatus = 'present' | 'absent' | 'excused';

export interface Session {
  id: string;
  course_id: string;
  title: string;
  program_day: number | null;
  description: string;
  starts_at: string;
  ends_at: string;
  meet_url?: string | null;
  status: SessionStatus;
  academy_courses: { name: string };
  academy_session_recovery?: {
    recording_url: string | null;
    material_url: string | null;
  } | null;
}

export interface Agenda {
  upcoming: Session[];
  past: Session[];
  hasNext: boolean;
}

export interface Administration {
  courses: { id: string; name: string }[];
  sessions: Session[];
  selected: Session | null;
  hasNext: boolean;
}

export interface Roster {
  items: { student_id: string; full_name: string; google_email: string; attendance: AttendanceStatus | null }[];
  hasNext: boolean;
}
