// Contenido editable de la página principal. Cambia aquí los textos sin tocar el diseño.

// Número de WhatsApp con código de país y sin "+" ni espacios (ej. Perú: 51987654321).
// Mientras esté vacío, el botón flotante y los enlaces de WhatsApp no se muestran.
export const WHATSAPP_NUMBER = '';
export const WHATSAPP_MESSAGE = 'Hola, quiero más información sobre SABERO Academy.';

// Correo público de contacto (se muestra en las páginas legales si se completa).
export const CONTACT_EMAIL = '';

export const whatsappUrl = WHATSAPP_NUMBER
  ? `https://wa.me/${WHATSAPP_NUMBER}?text=${encodeURIComponent(WHATSAPP_MESSAGE)}`
  : null;

export const about = {
  kicker: 'Nosotros',
  title: 'Formación con criterio profesional',
  paragraphs: [
    'SABERO Consulting diseña programas de formación privados para profesionales que quieren avanzar con método, acompañamiento y resultados medibles.',
    'SABERO Academy es nuestro campus: un espacio exclusivo donde cada alumno accede a sus cursos, sesiones en vivo y materiales, con seguimiento cercano de principio a fin.',
  ],
  stats: [
    { value: '100%', label: 'Acceso privado y verificado' },
    { value: 'En vivo', label: 'Sesiones con acompañamiento' },
    { value: '24/7', label: 'Campus disponible' },
  ],
};

export const services = [
  { icon: 'book', title: 'Formación a medida', text: 'Programas estructurados en cursos, módulos y lecciones, pensados para que avances paso a paso.' },
  { icon: 'live', title: 'Sesiones en vivo', text: 'Clases por videollamada con agenda clara, enlaces directos y recuperación de lo visto.' },
  { icon: 'folder', title: 'Campus y recursos', text: 'Documentos, guías y grabaciones organizados por curso, disponibles cuando los necesites.' },
  { icon: 'chat', title: 'Consultas y acompañamiento', text: 'Un canal directo con el equipo para resolver dudas y mantener tu avance.' },
];

export const vision = {
  kicker: 'Visión',
  title: 'Ser la academia de referencia para profesionales exigentes',
  text: 'Aspiramos a que cada persona que se forma con nosotros logre un crecimiento real y sostenido, apoyado en contenido de calidad, tecnología cuidada y cercanía humana.',
  values: [
    { title: 'Excelencia', text: 'Contenido riguroso y actualizado, revisado antes de publicarse.' },
    { title: 'Cercanía', text: 'Acompañamiento real, no un curso que se queda solo en un video.' },
    { title: 'Confianza', text: 'Acceso privado y datos tratados con respeto y transparencia.' },
  ],
};

// Comentarios REALES de alumnos. Añade aquí solo testimonios autorizados por quien los escribió.
export const testimonials: { name: string; role: string; text: string }[] = [];
