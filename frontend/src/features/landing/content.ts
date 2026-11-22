// Contenido editable de la página principal y del pie de página. Cambia aquí los textos sin tocar el diseño.

// Número de WhatsApp con código de país y sin "+" ni espacios (ej. Perú: 51987654321).
// Mientras esté vacío, el botón flotante y los enlaces de WhatsApp no se muestran.
export const WHATSAPP_NUMBER = '51923327532';
export const WHATSAPP_MESSAGE = 'Hola, quiero más información sobre SABERO Academy.';

// Correo público de contacto (se muestra en el pie y en las páginas legales).
export const CONTACT_EMAIL = 'gerencia@saberoconsulting.com';

export const whatsappUrl = WHATSAPP_NUMBER
  ? `https://wa.me/${WHATSAPP_NUMBER}?text=${encodeURIComponent(WHATSAPP_MESSAGE)}`
  : null;

export const hero = {
  badge: 'Formación privada · Agentes de IA para ventas',
  title: 'Crea tu agente de IA que vende por ti',
  intro: 'Aprende a construir un agente que atiende a tus clientes en WhatsApp, da seguimiento, agenda y registra todo en tu propio mini CRM. Con método, en vivo y acompañado.',
};

export const about = {
  kicker: 'Nosotros',
  title: 'Aprende a automatizar tus ventas con inteligencia artificial',
  paragraphs: [
    'SABERO Consulting forma a emprendedores y equipos comerciales para que dejen de depender de tareas manuales: construirás un agente de IA que atiende, hace seguimiento y ayuda a cerrar ventas.',
    'SABERO Academy es nuestro campus privado: cursos paso a paso, sesiones en vivo y recursos listos para usar, con acompañamiento cercano de principio a fin.',
  ],
  stats: [
    { value: '100% práctico', label: 'Aprendes construyendo tu propio agente' },
    { value: 'En vivo', label: 'Sesiones con acompañamiento' },
    { value: '24/7', label: 'Campus y materiales siempre disponibles' },
  ],
};

export const services = [
  { icon: 'bot', title: 'Agentes de ventas con IA', text: 'Diseña un agente que atiende consultas, califica clientes y conduce la conversación hasta la venta.' },
  { icon: 'chat', title: 'WhatsApp conectado', text: 'Conecta tu número de WhatsApp para que el agente responda al instante, a cualquier hora.' },
  { icon: 'network', title: 'Automatización con Meta', text: 'Integra Instagram, Facebook y tus anuncios para captar y atender clientes potenciales automáticamente.' },
  { icon: 'repeat', title: 'Seguimientos automáticos', text: 'Recordatorios y mensajes de seguimiento que reactivan clientes sin que tengas que escribir uno por uno.' },
  { icon: 'crm', title: 'Mini CRM propio', text: 'Registra clientes, etapas de venta e historial de conversaciones en un panel simple y tuyo.' },
  { icon: 'web', title: 'Creación de webs', text: 'Construye páginas que captan clientes y se conectan con tu agente y tu CRM.' },
];

export const vision = {
  kicker: 'Visión',
  title: 'Que cada negocio venda más con ayuda de la IA',
  text: 'Aspiramos a que cualquier emprendedor o equipo comercial pueda tener su propio sistema de ventas automatizado, entendiendo cómo funciona y siendo dueño de él.',
  values: [
    { title: 'Resultados', text: 'Cada módulo termina en algo que funciona: un agente, una automatización, un panel.' },
    { title: 'Cercanía', text: 'Acompañamiento real en sesiones en vivo y consultas, no solo videos grabados.' },
    { title: 'Confianza', text: 'Acceso privado y datos tratados con respeto y transparencia.' },
  ],
};

// Comentarios del carrusel (máximo 8). Los actuales son de EJEMPLO (sample: true) y se muestran como ilustrativos.
// Para publicar comentarios reales: reemplaza estas entradas y quita "sample: true".
export const testimonials: { name: string; role: string; text: string; sample?: boolean }[] = [
  { sample: true, name: 'Lucía Fernández', role: 'Dueña de tienda online', text: 'Mi agente ya responde por WhatsApp mientras duermo. Antes perdía clientes por tardar en contestar.' },
  { sample: true, name: 'Carlos Mendoza', role: 'Jefe comercial', text: 'El seguimiento automático nos devolvió ventas que dábamos por perdidas. Y lo configuramos en pocas semanas.' },
  { sample: true, name: 'Andrea Salazar', role: 'Consultora independiente', text: 'Armé mi mini CRM paso a paso y por fin tengo todos mis clientes ordenados en un solo lugar.' },
  { sample: true, name: 'Diego Paredes', role: 'Desarrollador freelance', text: 'Las sesiones en vivo resuelven las dudas al momento. Se nota que el contenido es práctico y está bien probado.' },
  { sample: true, name: 'Valeria Ríos', role: 'Directora de marketing', text: 'Conectar Meta con el agente nos ahorró horas diarias de atender mensajes repetidos.' },
  { sample: true, name: 'Jorge Castillo', role: 'Emprendedor', text: 'Lancé mi web y la conecté con mi agente. Ahora los interesados llegan y son atendidos de inmediato.' },
  { sample: true, name: 'Mariana Torres', role: 'Gerente de operaciones', text: 'Cada módulo deja algo listo para usar. En una semana ya estábamos probando el agente con clientes reales.' },
  { sample: true, name: 'Renato Vargas', role: 'Dueño de negocio local', text: 'No tenía experiencia técnica y aun así pude montar todo. El acompañamiento marca la diferencia.' },
];

// Pie de página profesional por columnas.
export type FooterLink = { label: string; href: string; external?: boolean };
export const footerColumns: { title: string; links: FooterLink[] }[] = [
  {
    title: 'La academia',
    links: [
      { label: '¿Quiénes somos?', href: '/#nosotros' },
      { label: 'Visión', href: '/#vision' },
      { label: 'Comentarios', href: '/#comentarios' },
      { label: 'Ponte en contacto con nosotros', href: '/#contacto' },
    ],
  },
  {
    title: 'Qué aprenderás',
    links: [
      { label: 'Agentes de ventas con IA', href: '/#servicios' },
      { label: 'WhatsApp conectado', href: '/#servicios' },
      { label: 'Automatización con Meta', href: '/#servicios' },
      { label: 'Mini CRM y seguimientos', href: '/#servicios' },
      { label: 'Creación de webs', href: '/#servicios' },
    ],
  },
  {
    title: 'Campus',
    links: [
      { label: 'Iniciar sesión', href: '/ingresar' },
      { label: 'Acceder al campus', href: '/ingresar' },
      { label: 'Ayuda y asistencia', href: '/#contacto' },
    ],
  },
  {
    title: 'Aspectos legales',
    links: [
      { label: 'Política de privacidad', href: '/privacidad' },
      { label: 'Términos del servicio', href: '/terminos' },
      { label: 'Mapa del sitio', href: '/sitemap.xml' },
    ],
  },
];
