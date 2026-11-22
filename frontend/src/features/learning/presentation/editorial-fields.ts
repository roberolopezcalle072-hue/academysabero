export type Entity = 'program' | 'course' | 'module' | 'lesson' | 'material';
export type FormValues = Record<string, string | number | boolean | string[] | null>;
type Field = [name: string, label: string, type?: 'long' | 'optional-long' | 'optional' | 'number' | 'price' | 'url' | 'status' | 'kind' | 'checkbox'];
export const formFields: Record<Entity, Field[]> = {
  program: [
    ['title', 'Título'], ['introduction', 'Presentación', 'long'], ['description', 'Descripción', 'long'],
    ['benefits', 'Beneficios, uno por línea', 'optional-long'], ['duration_text', 'Duración'],
    ['launch_price', 'Precio de lanzamiento', 'price'], ['currency', 'Moneda ISO (PEN, USD)', 'optional'],
    ['registration_text', 'Información de inscripción', 'long'], ['registration_url', 'Enlace de inscripción', 'url'],
    ['welcome_drive_file_id', 'ID del video público de bienvenida en Drive', 'optional'],
    ['published', 'Publicar en la landing', 'checkbox'],
  ],
  course: [
    ['name', 'Nombre'], ['description', 'Descripción', 'long'], ['image_path', 'Ruta local de imagen bajo /images/'],
    ['duration_minutes', 'Duración en minutos', 'number'], ['status', 'Estado', 'status'],
  ],
  module: [['title', 'Título'], ['position', 'Orden', 'number'], ['status', 'Estado', 'status']],
  lesson: [
    ['title', 'Título'], ['day_number', 'Día', 'number'], ['position', 'Orden', 'number'], ['status', 'Estado', 'status'],
    ['objective', 'Objetivo', 'optional-long'], ['description', 'Explicación', 'long'], ['prompt', 'Prompt del día', 'optional-long'],
    ['instructions', 'Instrucciones', 'optional-long'], ['deliverable', 'Entregable', 'optional-long'],
    ['validation_criteria', 'Criterios de validación', 'optional-long'],
  ],
  material: [['title', 'Título'], ['kind', 'Tipo', 'kind'], ['drive_url', 'Enlace privado de Google Drive', 'url'], ['position', 'Orden', 'number']],
};
export const statuses = { draft: 'Borrador', published: 'Publicado', archived: 'Archivado' };
export const materialKinds = { document: 'Documento', recording: 'Grabación', prompt: 'Prompt', other: 'Otro' };
