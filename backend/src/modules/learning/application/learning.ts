export interface LearningRepository {
  program(): Promise<unknown>;
  home(token: string): Promise<unknown>;
  course(token: string, id: string): Promise<unknown>;
  complete(token: string, id: string): Promise<boolean>;
  inquiries(token: string, student: string, page: number): Promise<unknown>;
  createInquiry(token: string, student: string, subject: string, body: string): Promise<void>;
}
