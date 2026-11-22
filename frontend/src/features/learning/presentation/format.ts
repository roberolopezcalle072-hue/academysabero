export function duration(minutes: number): string {
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return [hours ? `${hours} h` : '', remainder ? `${remainder} min` : ''].filter(Boolean).join(' ');
}

const dateTimeFormatter = new Intl.DateTimeFormat('es-PE', {
  dateStyle: 'long', timeStyle: 'short', timeZone: 'America/Lima',
});
export const dateTime = (value: string) => dateTimeFormatter.format(new Date(value));

export function lessonUrl(courseId: string, lessonId: string) {
  return `/campus/cursos/${encodeURIComponent(courseId)}?leccion=${encodeURIComponent(lessonId)}#leccion`;
}
