export const sessionStates = { draft: 'Borrador', scheduled: 'Programada', completed: 'Finalizada', cancelled: 'Cancelada' };
export const attendanceStates = { present: 'Presente', absent: 'Ausente', excused: 'Justificada' };

const localClock = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit',
});

export function limaInput(value?: string) {
  if (!value) return '';
  const parts = Object.fromEntries(localClock.formatToParts(new Date(value)).map(({ type, value }) => [type, value]));
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}
