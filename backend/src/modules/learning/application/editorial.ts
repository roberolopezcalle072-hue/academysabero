export const editorialTables = {
  program: 'academy_program_page',
  course: 'academy_courses',
  module: 'academy_modules',
  lesson: 'academy_lessons',
  material: 'academy_materials',
} as const;

export type EditorialEntity = keyof typeof editorialTables;
export type EditorialValue = string | number | boolean | string[] | null;
export type EditorialFields = Record<string, EditorialValue>;

export interface EditorialRepository {
  catalog(token: string, page: number, courseId?: string): Promise<unknown>;
  save(token: string, entity: EditorialEntity, fields: EditorialFields, id: string | null): Promise<boolean>;
}
