import { createAcademyClient } from '../../../platform/supabase/academy-client';
import { editorialTables, type EditorialEntity, type EditorialFields, type EditorialRepository } from '../application/editorial';

export class SupabaseEditorial implements EditorialRepository {
  constructor(private readonly url: string, private readonly key: string) {}

  async catalog(token: string, page: number, courseId?: string) {
    const client = this.client(token);
    const from = (page - 1) * 25;
    const [courses, program, course, modules, lessons, materials] = await Promise.all([
      client.from('academy_courses').select('id,name,status', { count: 'exact' }).order('name').order('id').range(from, from + 24),
      client.from('academy_program_page').select(
        'title,introduction,description,benefits,duration_text,launch_price,currency,registration_text,registration_url,welcome_drive_file_id,published',
      ).maybeSingle(),
      courseId && client.from('academy_courses').select('id,name,description,image_path,status,duration_minutes').eq('id', courseId).maybeSingle(),
      courseId && client.from('academy_modules').select('id,title,position,status').eq('course_id', courseId).order('position'),
      courseId && client.from('academy_lessons').select(
        'id,module_id,title,description,day_number,prompt,position,status,objective,instructions,deliverable,validation_criteria',
      ).eq('course_id', courseId).order('position'),
      courseId && client.from('academy_materials').select('id,lesson_id,title,kind,drive_url,position,academy_lessons!inner(course_id)')
        .eq('academy_lessons.course_id', courseId).order('position'),
    ]);
    for (const result of [courses, program, course, modules, lessons, materials]) {
      if (result && result.error) throw result.error;
    }
    return {
      courses: courses.data, program: program.data, hasNext: (courses.count ?? 0) > from + 25,
      course: course ? course.data : null, modules: modules ? modules.data : [],
      lessons: lessons ? lessons.data : [], materials: materials ? materials.data : [],
    };
  }

  async save(token: string, entity: EditorialEntity, fields: EditorialFields, id: string | null) {
    const table = this.client(token).from(editorialTables[entity]);
    if (entity === 'program') {
      const { error } = await table.upsert({ ...fields, singleton: true });
      if (error) throw error;
      return true;
    }
    const mutation = id ? table.update(fields).eq('id', id) : table.insert(fields);
    const { data, error } = await mutation.select('id').maybeSingle();
    if (error) throw error;
    return Boolean(data);
  }

  private client(accessToken: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}
