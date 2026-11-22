import { BadRequestException } from '@nestjs/common';
import type { EditorialEntity, EditorialFields } from '../application/editorial';

type Rule = 'text' | 'optional' | 'long' | 'optionalLong' | 'integer' | 'status' | 'uuid' | 'kind' | 'benefits' | 'price' | 'boolean';
const fields: Record<EditorialEntity, Record<string, Rule>> = {
  program: {
    title: 'text', introduction: 'long', description: 'long', benefits: 'benefits', duration_text: 'text',
    launch_price: 'price', currency: 'optional', registration_text: 'long', registration_url: 'text',
    welcome_drive_file_id: 'optional', published: 'boolean',
  },
  course: { name: 'text', description: 'long', image_path: 'text', status: 'status', duration_minutes: 'integer' },
  module: { course_id: 'uuid', title: 'text', position: 'integer', status: 'status' },
  lesson: {
    module_id: 'uuid', course_id: 'uuid', title: 'text', description: 'long', day_number: 'integer',
    prompt: 'optionalLong', position: 'integer', status: 'status', objective: 'optionalLong',
    instructions: 'optionalLong', deliverable: 'optionalLong', validation_criteria: 'optionalLong',
  },
  material: { lesson_id: 'uuid', title: 'text', kind: 'kind', drive_url: 'text', position: 'integer' },
};
const parents = new Set(['course_id', 'module_id', 'lesson_id']);

export const validId = (value: string) => /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value);

export function parseEditorial(entity: EditorialEntity, raw: Record<string, unknown>, updating: boolean): EditorialFields {
  const result: EditorialFields = {};
  for (const [key, rule] of Object.entries(fields[entity])) {
    if (updating && parents.has(key)) continue;
    if (typeof raw[key] !== 'string') throw new BadRequestException();
    const value = String(raw[key]).trim();
    if (rule === 'boolean') {
      if (value !== 'true' && value !== 'false') throw new BadRequestException();
      result[key] = value === 'true';
    } else if (rule === 'benefits') {
      if (value.length > 6000) throw new BadRequestException();
      result[key] = value.split('\n').map(line => line.trim()).filter(Boolean);
    } else if (rule === 'integer') {
      if (!/^[1-9]\d{0,8}$/.test(value)) throw new BadRequestException();
      result[key] = Number(value);
    } else if (rule === 'price') {
      if (value && !/^\d{1,10}(\.\d{1,2})?$/.test(value)) throw new BadRequestException();
      result[key] = value ? Number(value) : null;
    } else {
      const allowed = rule === 'status' ? ['draft', 'published', 'archived'] :
        rule === 'kind' ? ['document', 'recording', 'prompt', 'other'] : null;
      const optional = rule === 'optional' || rule === 'optionalLong';
      const limit = rule === 'long' || rule === 'optionalLong' ? 20000 : 2048;
      if ((!optional && !value) || value.length > limit || (allowed && !allowed.includes(value)) ||
          (rule === 'uuid' && !validId(value))) throw new BadRequestException();
      result[key] = value || null;
    }
  }
  return result;
}
