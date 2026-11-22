export interface SessionDetails {
  course: string;
  title: string;
  day: number;
  description: string;
  starts: string;
  ends: string;
  meet: string | null;
  status: 'draft' | 'scheduled' | 'completed';
  recording: string | null;
  material: string | null;
}

export type AttendanceStatus = 'present' | 'absent' | 'excused';

export interface LiveTrainingRepository {
  agenda(token: string, page: number): Promise<unknown>;
  administration(token: string, page: number, session?: string): Promise<unknown>;
  roster(token: string, session: string, page: number, presentOnly: boolean): Promise<unknown>;
  save(token: string, session: string | null, details: SessionDetails): Promise<string | null>;
  cancel(token: string, session: string): Promise<boolean>;
  recordAttendance(token: string, session: string, student: string, status: AttendanceStatus): Promise<boolean>;
}
