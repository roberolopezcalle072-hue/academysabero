// Contenido editable de la página principal. Cambia aquí los textos sin tocar el diseño.

// Número de WhatsApp con código de país y sin "+" ni espacios (ej. Perú: 51987654321).
// Mientras esté vacío, el botón flotante y los enlaces de WhatsApp no se muestran.
export const WHATSAPP_NUMBER = '51923327532';
export const WHATSAPP_MESSAGE = 'Hola, quiero más información sobre SABERO Academy.';

// Correo público de contacto (se muestra en las páginas legales si se completa).
export const CONTACT_EMAIL = 'gerencia@saberoconsulting.com';

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

// Comentarios del carrusel (máximo 8). Los actuales son de EJEMPLO (sample: true) y muestran una etiqueta "Ejemplo".
// Para publicar comentarios reales: reemplaza estas entradas y quita "sample: true".
export const testimonials: { name: string; role: string; text: string; sample?: boolean }[] = [
  { sample: true, name: 'Lucía Fernández', role: 'Analista de datos', text: 'Las sesiones en vivo son claras y el campus me permite retomar cada clase cuando lo necesito. Se nota el cuidado en el contenido.' },
  { sample: true, name: 'Carlos Mendoza', role: 'Jefe de proyectos', text: 'Lo que más valoro es el acompañamiento: cada consulta recibió respuesta rápida y orientada a mi caso real.' },
  { sample: true, name: 'Andrea Salazar', role: 'Consultora independiente', text: 'Un programa ordenado, con materiales muy bien organizados. Pasé de la teoría a aplicarlo en mi trabajo en pocas semanas.' },
  { sample: true, name: 'Diego Paredes', role: 'Ingeniero de software', text: 'Me gustó la mezcla de clases en vivo y recursos para repasar. Todo está al alcance en un solo lugar.' },
  { sample: true, name: 'Valeria Ríos', role: 'Directora comercial', text: 'Contenido riguroso y un trato cercano. Recomiendo la academia a quien busque crecer con método.' },
  { sample: true, name: 'Jorge Castillo', role: 'Emprendedor', text: 'La plataforma es sencilla y elegante. Seguir mi progreso curso a curso me mantuvo constante.' },
  { sample: true, name: 'Mariana Torres', role: 'Gerente de operaciones', text: 'Las explicaciones son prácticas y directas. Cada módulo deja herramientas que puedo usar al día siguiente.' },
  { sample: true, name: 'Renato Vargas', role: 'Analista financiero', text: 'Excelente experiencia: sesiones bien preparadas, buen ritmo y un equipo siempre disponible para resolver dudas.' },
];
