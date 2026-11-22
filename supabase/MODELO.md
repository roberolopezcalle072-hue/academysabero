# Modelo de datos de SABERO ACADEMY

PostgreSQL 15 o superior en Supabase. NestJS sigue siendo la API del campus y usa los tokens de la sesión para que PostgreSQL aplique RLS. Astro consume la API de NestJS. La credencial de aplicación es la clave publicable de Supabase.

## Entidades y relaciones

| Entidad | Relación y reglas |
| --- | --- |
| Administradores · `academy_administrators` | Vista de las membresías con rol `admin`. La clave es el UUID de `auth.users`. |
| Alumnos · `academy_student_profiles` | Vista de `academy_students` y `academy_members`. Expone UUID, nombre, correo de Google normalizado y único, acceso y fecha de registro. La clave foránea compuesta exige rol `student`. |
| Correos autorizados · `academy_authorized_emails` | Lista de correos únicos normalizados, con estado activo. Su consulta y gestión son administrativas. Controla el alta y el acceso posterior de alumnos. Las asociaciones pendientes por correo se registran en `academy_email_enrollments`. |
| Códigos de matrícula · `academy_enrollment_codes` | SHA-256 hex del código, inscripción y estado `active`, `used` o `revoked`. El código se puede sustituir tras revocarse. Después de un canje exitoso la inscripción no admite otro código activo. |
| Cursos · `academy_courses` | Nombre, descripción, ruta local bajo `/images/`, estado y duración positiva en minutos. |
| Módulos · `academy_modules` | Pertenecen a un curso. Tienen título, estado y posición única por curso. |
| Lecciones · `academy_lessons` | Pertenecen a un módulo del mismo curso. Tienen título, descripción, día, prompt opcional, estado y posición única por módulo. |
| Materiales · `academy_materials` | Pertenecen a una lección. Registran tipo, título, enlace HTTPS de Drive o Docs y posición única por lección. |
| Sesiones en vivo · `academy_live_sessions` | Pertenecen a un curso. Registran estado, horario y enlace HTTPS de Meet. El fin debe ser posterior al inicio. |
| Inscripciones · `academy_enrollments` | Una por alumno y curso. La fecha de inscripción es obligatoria para los estados `active` y `completed`. `academy_enrollment_overview` añade el porcentaje de avance. |
| Progreso · `academy_progress` | Una fila por alumno y lección. Exige inscripción al curso de la lección. La fecha de finalización existe si la lección está completada. |
| Asistencia · `academy_attendance` | Una fila por alumno y sesión. Exige inscripción al curso de la sesión. Registra presencia, ausencia o justificación. |
| Consultas · `academy_inquiries` | Pertenecen a un alumno y pueden asociarse a un curso en el que exista una inscripción. Registran asunto, mensaje y estado. |
| Respuestas · `academy_inquiry_replies` | Pertenecen a una consulta y referencian a un miembro con rol administrativo. Las inserciones de la API quedan atribuidas al administrador autenticado. |

Las tablas tienen fechas de creación y actualización en `timestamptz`. PostgreSQL actualiza la última fecha mediante disparadores. Las claves compuestas impiden registrar progreso o asistencia de otro curso. Los índices apoyan la navegación por curso y lección, la agenda, las relaciones con inscripciones y la lectura de consultas.

El avance se calcula al consultar, como porcentaje de lecciones completadas entre las lecciones publicadas de módulos publicados de un curso publicado. Se devuelve cero cuando no hay lecciones computables. Los cambios de publicación pueden modificar ese porcentaje.

## Acceso

| Actor | Alcance |
| --- | --- |
| Administrador activo | Lee todos los alumnos y el resto del modelo. Puede insertar y actualizar datos académicos mediante las políticas administrativas, emitir y revocar códigos y registrar sus respuestas. |
| Alumno con correo autorizado y al menos una matrícula activa | Lee su perfil, inscripciones, historial de progreso y asistencia, consultas y respuestas propias. Lee el contenido publicado de cursos con inscripción activa y sus sesiones programadas o finalizadas. Puede canjear un código asignado a su propia inscripción. |
| Cuenta sin membresía activa o visitante | Carece de acceso a los datos académicos. |
| Operador autorizado de Supabase | Otorga y desactiva membresías. Al insertar una membresía de alumno, PostgreSQL exige una identidad Google con correo y crea el perfil desde esa identidad. |

La migración recupera los perfiles de las membresías previas que ya tienen una identidad de Google con correo. Las membresías anteriores sin esa identidad se conservan para mantener el acceso previo de NestJS. Su perfil académico requiere regularización por un operador antes de crear inscripciones. Las vistas aplican las políticas de sus tablas subyacentes con `security_invoker`. Los cambios de rol y las eliminaciones quedan reservados al operador y sujetos a las claves foráneas.

Para emitir un código, NestJS puede generar un valor aleatorio de alta entropía con entre 32 y 128 caracteres URL-safe y guardar su SHA-256 hexadecimal. El RPC `academy_redeem_enrollment_code` usa el token del alumno, bloquea el código activo y activa la inscripción pendiente en la misma transacción que lo marca como utilizado. Devuelve el UUID del curso si se canjea y `null` si el código no cumple las condiciones. El código en claro se entrega al destinatario una vez.

## Migrar y verificar

En Supabase SQL Editor aplica los archivos de `migrations/` en orden ascendente. Si el proyecto ya tiene `academy_members` del Prompt 01, empieza en `20261121000200_academic_model.sql`. Ejecuta después `verify_academic_model.sql` como propietario de la base. El script comprueba claves foráneas compuestas, RLS, permisos, vistas y el comportamiento de una sesión sin identidad. No requiere datos de prueba.

Para validar el acceso con usuarios reales, repite las consultas en una transacción con el rol `authenticated` y los claims de un alumno o administrador ya autorizado. Comprueba que el alumno ve solo sus filas, que el administrador ve todos los perfiles y que una inscripción pendiente no muestra el contenido del curso. El proyecto y sus usuarios son necesarios para verificar esos casos.

[Documentación de RLS de Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security)

La [guía de acceso privado](ACCESO.md) detalla las asignaciones por correo, la vigencia de las sesiones y el hook de Supabase Auth.
